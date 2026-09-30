#!/usr/bin/env bash
# Launch one mission. The human runs this once; everything after is unattended.
#   validates BRIEF.yaml -> .claude/state/brief.json
#   starts the lead headlessly (or resumes it by session id), with the settings.json allow list passed via
#     --allowedTools because a never-trusted folder ignores project allow rules in -p mode
#   runs the overseer beside the lead (QS_OVERSEER=0 disables; QS_OVERSEER_MIN sets its interval, default 15)
#   backs off exponentially on restarts (QS_SLEEP overrides) and writes SAFE_STOP after 5
# Exit: 0 lead returned, 2 brief invalid, 3 gave up (restart limit), else the lead's exit code.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2
export CLAUDE_PROJECT_DIR="$PWD"
S=.claude/state; mkdir -p "$S" docs/ledgers
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
git config core.longpaths true 2>/dev/null

"$PY" scripts/brief.py validate || { echo "run: BRIEF.yaml invalid or missing" >&2; exit 2; }
# a terminal RUN_STATE left by an earlier, merged mission (different goal) is moved to docs/runs/ so this one starts fresh
arch="$("$PY" scripts/ledger.py archive-stale)" || { echo "run: cannot check for a stale run" >&2; exit 2; }
case "$arch" in archived*) echo "run: previous mission $arch";; esac

terminal() { grep -Eq '"state": ?"(DONE|DONE_PARTIAL|SAFE_STOP|HALT)"' docs/RUN_STATE 2>/dev/null; }
if terminal; then echo "run: already terminal: $(cat docs/RUN_STATE)"; exit 0; fi

n="$(cat "$S/restarts" 2>/dev/null || echo 0)"; n="${n//[!0-9]/}"; n="${n:-0}"
if [ "$n" -ge 5 ]; then
  printf '{"state":"SAFE_STOP","reason":"restart limit (5) reached","at":"%s"}\n' "$(date -u +%FT%TZ)" > docs/RUN_STATE
  echo "run: restart limit reached, wrote SAFE_STOP" >&2; exit 3
fi
[ "$n" -gt 0 ] && sleep "${QS_SLEEP:-$((2 ** n))}"
echo $((n + 1)) > "$S/restarts"

allow="$("$PY" -c 'import json; print(",".join(json.load(open(".claude/settings.json"))["permissions"]["allow"]))')"
allow="${allow//$'\r'/}"
# --strict-mcp-config with an empty config: the lead gets the repo's tools only, not the operator's connectors
# (hundreds of MCP tool schemas per turn cost real money and are not part of any mission).
common=(--permission-mode acceptEdits --permission-prompts none --allowedTools "$allow" --output-format json
        --mcp-config '{"mcpServers":{}}' --strict-mcp-config)

ov_pid=""
if [ "${QS_OVERSEER:-1}" = 1 ] && [ -f scripts/overseer.sh ]; then
  bash scripts/overseer.sh --loop "${QS_OVERSEER_MIN:-15}" >> "$S/overseer.log" 2>&1 &
  ov_pid=$!
fi
trap '[ -n "$ov_pid" ] && kill "$ov_pid" 2>/dev/null' EXIT

start_prompt="Start the mission described in BRIEF.yaml. Follow the Lead loop in CLAUDE.md from step 0. Nobody is reading; never ask a question."
resume_prompt="Resume the mission. Start at step 1 (Resume) of the Lead loop in CLAUDE.md. Nobody is reading; never ask a question."
rc=0
if [ -s "$S/session_id" ]; then
  sid="$(tr -d '\r\n ' < "$S/session_id")"
  claude -p "$resume_prompt" --resume "$sid" "${common[@]}" > "$S/last_run.json"; rc=$?
  if [ "$rc" -ne 0 ] && ! grep -q '"session_id"' "$S/last_run.json" 2>/dev/null; then
    echo "run: resume of $sid failed (exit $rc); starting fresh from the ledgers" >&2
    rm -f "$S/session_id"
    claude -p "$resume_prompt" "${common[@]}" > "$S/last_run.json"; rc=$?
  fi
else
  claude -p "$start_prompt" "${common[@]}" > "$S/last_run.json"; rc=$?
fi

sid="$("$PY" -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("session_id",""))
except Exception: print("")' "$S/last_run.json")"; sid="${sid//$'\r'/}"
if [ -z "$sid" ] && [ -s "$S/transcript_path" ]; then
  # killed mid-run: no JSON result, but the budget hook recorded the transcript path, whose basename is the session id
  tp="$(tr -d '\r\n' < "$S/transcript_path")"; tp="${tp//\\//}"; tp="${tp##*/}"; sid="${tp%.jsonl}"
fi
[ -n "$sid" ] && printf '%s\n' "$sid" > "$S/session_id"

echo "run: lead exit=$rc state=$(cat docs/RUN_STATE 2>/dev/null || echo none)"
exit "$rc"
