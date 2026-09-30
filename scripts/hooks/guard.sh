#!/usr/bin/env bash
# PreToolUse/PostToolUse guard. Enforces the CLAUDE.md hard rules from inside the repo, so they hold in cloud
# sessions and fresh clones where ~/.claude settings do not exist. Fails closed: malformed input -> exit 2.
# Input: hook JSON on stdin. Exit 0 = allow, exit 2 = deny (reason on stderr).
#
# Clauses, in order:  1 hard rules (always)   2 overseer cancel flag   3 plan/act tier   4 lethal-trifecta legs.
# Clauses 2-4 act only when their state file exists (.claude/state/{cancel,tier,current_step.json}), i.e. during a run.
# PostToolUse never denies; it only records the leg a tool call used (clause 4).
set -u
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
in="$(cat)"
parsed="$(printf '%s' "$in" | "$PY" -c '
import json, sys
d = json.load(sys.stdin); e = d.get("hook_event_name", "PreToolUse"); t = d["tool_name"]; i = d["tool_input"]
if t == "Bash": v = i["command"]
elif t in ("Write", "Edit", "MultiEdit", "Read"): v = i["file_path"]
else: v = i.get("url") or i.get("query") or ""
print(e); print(t); print(str(v))
' 2>/dev/null)" || { echo "guard: malformed hook input, denied" >&2; exit 2; }
parsed="${parsed//$'\r'/}"   # python on Windows emits CRLF
event="${parsed%%$'\n'*}"; rest="${parsed#*$'\n'}"
tool="${rest%%$'\n'*}"; raw="${rest#*$'\n'}"; arg="${raw//$'\n'/ }"   # raw keeps newlines for the split
case "$tool" in Write|Edit|MultiEdit|Read) arg="${arg//\\//}";; esac   # Windows tools pass backslash paths
S="${CLAUDE_PROJECT_DIR:-.}/.claude/state"; mkdir -p "$S" 2>/dev/null
# Subcommands of a Bash line, one per element of SEGS: split on && || ; | |& and newlines (as Claude Code matches
# permission rules), leading space trimmed, and git's -C <dir> / -c <k=v> / --git-dir / --work-tree options dropped
# so `git -C wt push` is matched as `git push`.
SEGS=()
split_subcmds() {
  local seg q='("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)'
  local opt_re="(^|[[:space:]])git[[:space:]]+(-C[[:space:]]+$q|-c[[:space:]]+$q|--(git-dir|work-tree)(=|[[:space:]]+)$q)[[:space:]]*"
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"; [ -z "$seg" ] && continue
    while [[ "$seg" =~ $opt_re ]]; do seg="${seg/"${BASH_REMATCH[0]}"/${BASH_REMATCH[1]}git }"; done
    SEGS+=("$seg")
  done < <(printf '%s\n' "$raw" | sed -E 's/(&&|\|\||\|&|;|\|)/\n/g')
}
[ "$tool" = Bash ] && split_subcmds
deny() { echo "guard: denied ($1): $tool $arg" >&2; exit 2; }
is_env_file() { # basename is .env or .env.<x>, except *.example|sample|template
  local b="${1##*/}"
  [[ "$b" =~ ^\.env(\..+)?$ ]] && ! [[ "$b" =~ \.(example|sample|template)$ ]]
}
leg_of() { # untrusted_content | outbound | none, for this tool call
  case "$tool" in
    WebFetch|WebSearch) echo untrusted_content;;
    Read) [[ "$arg" =~ (^|/)work/_untrusted/ ]] && echo untrusted_content || echo none;;
    Bash) # per subcommand; outbound in any subcommand wins over untrusted_content
      local seg l=none
      for seg in "${SEGS[@]}"; do
        if [[ "$seg" =~ git[[:space:]]+push|gh[[:space:]]+(pr|issue|release)[[:space:]]+(create|comment|edit|merge|close)|npm[[:space:]]+publish ]]; then echo outbound; return
        elif [[ "$seg" =~ (^|[[:space:]])curl[[:space:]] ]] && [[ "$seg" =~ -X[[:space:]]*(POST|PUT|PATCH|DELETE)|--data|[[:space:]]-d[[:space:]]|--upload-file|[[:space:]]-T[[:space:]] ]]; then echo outbound; return
        elif [[ "$seg" =~ (^|[[:space:]])(curl|wget)[[:space:]] || "$seg" =~ work/_untrusted/ ]]; then l=untrusted_content; fi
      done
      echo "$l";;
    *) echo none;;
  esac
}

# --- PostToolUse: record the leg for the current step, never deny ---
if [ "$event" = PostToolUse ]; then
  if [ -f "$S/current_step.json" ]; then
    sid="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id","nostep"))' "$S/current_step.json" 2>/dev/null)"; sid="${sid//$'\r'/}"
    leg="$(leg_of)"; mkdir -p "$S/legs"
    [ "$leg" != none ] && [ -n "$sid" ] && echo "$leg" >> "$S/legs/$sid"
  fi
  exit 0
fi

printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$tool" "$arg" >> "$S/hook_log" 2>/dev/null

# --- 1. hard rules ---
case "$tool" in
  Bash) # each rule sees one subcommand, so a token in another subcommand can neither trip nor mask it
    for seg in "${SEGS[@]}"; do
      if [[ "$seg" =~ git[[:space:]]+push ]]; then
        [[ "$seg" =~ [[:space:]](--force|--force-with-lease|-f)([[:space:]]|$) || "$seg" =~ [[:space:]]\+[^[:space:]] ]] && deny "force push"
        [[ "$seg" =~ ([[:space:]]|:)(main|master)([[:space:]]|$) ]] && deny "push to main"
      fi
      [[ "$seg" =~ git[[:space:]]+reset[[:space:]]+--hard ]] && deny "git reset --hard"
      [[ "$seg" =~ git[[:space:]]+branch[[:space:]]+(-D|--delete[[:space:]]+--force) ]] && deny "git branch -D"
      [[ "$seg" =~ git[[:space:]]+checkout[[:space:]]+--[[:space:]] ]] && deny "git checkout -- discards work"
      [[ "$seg" =~ git[[:space:]]+(filter-branch|filter-repo) ]] && deny "history rewrite"
      [[ "$seg" =~ (^|[[:space:]])pip3?[[:space:]]+install ]] && deny "pip install (use uv add)"
      [[ "$seg" =~ (^|[[:space:]])rm[[:space:]]+(-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r|-r[[:space:]]+-f|-f[[:space:]]+-r) ]] && deny "rm -rf"
    done
    for tok in $arg; do tok="${tok#[\"\']}"; tok="${tok%[\"\']}"; is_env_file "$tok" && deny ".env access"; done
    # Claude Code's permission layer treats a cd before any git command as needing approval, which an unattended
    # run cannot give; deny it here with the fix in the reason instead of an opaque permission failure.
    seen_cd=0
    for seg in "${SEGS[@]}"; do
      [[ "$seg" =~ ^cd([[:space:]]|$) ]] && seen_cd=1
      [ "$seen_cd" = 1 ] && [[ "$seg" =~ ^git([[:space:]]|$) ]] && deny "cd before git is auto-denied in an unattended run; use git -C <dir> ... instead"
    done
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

# Clauses 2-4 are mission-run policy for the lead and its subagents; the overseer session (QS_ROLE=overseer) is exempt.
[ "${QS_ROLE:-lead}" = overseer ] && exit 0

# --- 2. overseer cancel: only reads and the final report may proceed ---
if [ -f "$S/cancel" ]; then
  case "$tool" in
    Read|Glob|Grep) ;;
    Write|Edit|MultiEdit) [[ "$arg" =~ docs/(REPORT\.md|RUN_STATE)$ ]] || deny "overseer cancel: only docs/REPORT.md and docs/RUN_STATE may be written";;
    *) deny "overseer cancel: the run is stopping";;
  esac
fi

# --- 3. plan tier: read-only, except the plan, the ledgers and the state dir ---
tier="$(cat "$S/tier" 2>/dev/null)"; tier="${tier//[$'\r\n ']/}"
if [ "$tier" = plan ]; then
  ro_re='^(git[[:space:]]+(status|log|diff|ls-files|rev-parse|show|branch([[:space:]]+--list)?|worktree[[:space:]]+list)|ls|cat|head|tail|wc|grep|rg|find|pwd|echo|tr|sort|uniq|cut|awk|sed[[:space:]]+-n|bash[[:space:]]+scripts/(gate|diffbase)\.sh|bash[[:space:]]+tests/|python3?[[:space:]]+scripts/(ledger|budget|brief|check_criteria)\.py)([[:space:]]|$)'
  case "$tool" in
    Read|Glob|Grep) ;;
    Write|Edit|MultiEdit) [[ "$arg" =~ (^|/)(docs/plan\.md|docs/ledgers/|\.claude/state/) ]] || deny "plan tier: cannot write $arg";;
    Bash)
      if [[ "$arg" =~ \> ]] && ! [[ "$arg" =~ \>[[:space:]]*\.claude/state/ ]]; then deny "plan tier: no redirects"; fi
      [[ "$arg" =~ [[:space:]]tee[[:space:]] ]] && deny "plan tier: no redirects"
      for seg in "${SEGS[@]}"; do [[ "$seg" =~ $ro_re ]] || deny "plan tier: read-only commands only ($seg)"; done
      ;;
    *) deny "plan tier: $tool not allowed";;
  esac
fi

# --- 4. lethal trifecta: one step never both reads untrusted content and sends data out ---
if [ -f "$S/current_step.json" ]; then
  stepinfo="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("id","nostep")); print(",".join(d.get("legs",[])))' "$S/current_step.json" 2>/dev/null)"
  stepinfo="${stepinfo//$'\r'/}"; sid="${stepinfo%%$'\n'*}"; declared="${stepinfo#*$'\n'}"
  leg="$(leg_of)"
  if [ "$leg" != none ]; then
    have=",$declared,$(tr '\n' ',' < "$S/legs/$sid" 2>/dev/null),"
    other=untrusted_content; [ "$leg" = untrusted_content ] && other=outbound
    [[ "$have" == *",$other,"* ]] && deny "trifecta: step $sid already used $other, so $leg is not allowed in the same step"
  fi
fi
exit 0
