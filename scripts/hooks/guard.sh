#!/usr/bin/env bash
# PreToolUse guard. Enforces the CLAUDE.md hard rules from inside the repo, so they hold in cloud
# sessions and fresh clones where ~/.claude settings do not exist. Fails closed: malformed input -> exit 2.
# Input: hook JSON on stdin. Exit 0 = allow, exit 2 = deny (reason on stderr).
set -u
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
in="$(cat)"
parsed="$(printf '%s' "$in" | "$PY" -c '
import json, sys
d = json.load(sys.stdin); t = d["tool_name"]; i = d["tool_input"]
if t == "Bash": v = i["command"]
elif t in ("Write", "Edit", "MultiEdit", "Read"): v = i["file_path"]
else: v = i.get("url") or i.get("query") or ""
print(t); print(str(v).replace("\n", " "))
' 2>/dev/null)" || { echo "guard: malformed hook input, denied" >&2; exit 2; }
parsed="${parsed//$'\r'/}"   # python on Windows emits CRLF
tool="${parsed%%$'\n'*}"; arg="${parsed#*$'\n'}"
S="${CLAUDE_PROJECT_DIR:-.}/.claude/state"; mkdir -p "$S" 2>/dev/null
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$tool" "$arg" >> "$S/hook_log" 2>/dev/null
deny() { echo "guard: denied ($1): $tool $arg" >&2; exit 2; }
is_env_file() { # basename is .env or .env.<x>, except *.example|sample|template
  local b="${1##*/}"
  [[ "$b" =~ ^\.env(\..+)?$ ]] && ! [[ "$b" =~ \.(example|sample|template)$ ]]
}
case "$tool" in
  Bash)
    if [[ "$arg" =~ git[[:space:]]+push ]]; then
      [[ "$arg" =~ [[:space:]](--force|--force-with-lease|-f)([[:space:]]|$) || "$arg" =~ [[:space:]]\+[^[:space:]] ]] && deny "force push"
      [[ "$arg" =~ ([[:space:]]|:)(main|master)([[:space:]]|$) ]] && deny "push to main"
    fi
    [[ "$arg" =~ git[[:space:]]+reset[[:space:]]+--hard ]] && deny "git reset --hard"
    [[ "$arg" =~ git[[:space:]]+branch[[:space:]]+(-D|--delete[[:space:]]+--force) ]] && deny "git branch -D"
    [[ "$arg" =~ git[[:space:]]+checkout[[:space:]]+--[[:space:]] ]] && deny "git checkout -- discards work"
    [[ "$arg" =~ git[[:space:]]+(filter-branch|filter-repo) ]] && deny "history rewrite"
    [[ "$arg" =~ (^|[[:space:]])pip3?[[:space:]]+install ]] && deny "pip install (use uv add)"
    [[ "$arg" =~ (^|[[:space:]])rm[[:space:]]+(-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r|-r[[:space:]]+-f|-f[[:space:]]+-r) ]] && deny "rm -rf"
    for tok in $arg; do tok="${tok#[\"\']}"; tok="${tok%[\"\']}"; is_env_file "$tok" && deny ".env access"; done
    ;;
  Write|Edit|MultiEdit|Read)
    is_env_file "$arg" && deny ".env access"
    if [ "$tool" != Read ]; then
      b="${arg##*/}"
      [[ "$b" =~ ^(vercel\.json|fly\.toml|netlify\.toml)$ ]] && deny "hosting config"
      [[ "$b" =~ ^Dockerfile.*(deploy|prod) ]] && deny "deploy Dockerfile"
      [[ "$arg" =~ (^|/)(infra|terraform|k8s)/ ]] && deny "infra config"
      [[ "$arg" =~ \.github/workflows/[^/]*deploy ]] && deny "deploy workflow"
    fi
    ;;
esac
exit 0
