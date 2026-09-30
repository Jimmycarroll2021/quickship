#!/usr/bin/env bash
# Runs the overseer: an independent watchdog check over a running mission.
# See docs/design/contracts.md > Overseer.
# Usage: overseer.sh            one tick, exit 0/1
#        overseer.sh --loop N   repeat every N minutes until docs/RUN_STATE is terminal
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
if [ -z "$ROOT" ]; then
  echo "overseer: cannot resolve repo root (set CLAUDE_PROJECT_DIR or run inside a git repo)" >&2
  exit 1
fi
cd "$ROOT" || { echo "overseer: cannot cd to $ROOT" >&2; exit 1; }

PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
S="$ROOT/.claude/state"

LOOP_MIN=""
if [ "${1:-}" = "--loop" ]; then
  LOOP_MIN="${2:-}"
  if [ -z "$LOOP_MIN" ]; then
    echo "overseer: --loop requires a minutes argument" >&2
    exit 1
  fi
fi

# is_terminal_run_state: 0 (true) when docs/RUN_STATE holds one of the terminal states.
is_terminal_run_state() {
  [ -f "$ROOT/docs/RUN_STATE" ] || return 1
  local state
  state="$("$PY" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    print(d.get("state", ""))
except Exception:
    print("")
' "$ROOT/docs/RUN_STATE" 2>/dev/null)"
  state="${state//$'\r'/}"
  case "$state" in
    DONE|DONE_PARTIAL|SAFE_STOP|HALT) return 0 ;;
    *) return 1 ;;
  esac
}

# do_tick: runs one overseer invocation. Exits 0 when nothing to watch or the
# overseer's result JSON has is_error:false; exits 1 when is_error:true.
do_tick() {
  mkdir -p "$S"

  if [ ! -f "$S/brief.json" ]; then
    echo "overseer: no active run ($S/brief.json absent), nothing to watch"
    return 0
  fi
  if is_terminal_run_state; then
    echo "overseer: run already terminal (docs/RUN_STATE), nothing to watch"
    return 0
  fi

  local prompt result exit_code ts is_error
  prompt="$(cat "$ROOT/.claude/agents/overseer.md")"

  result="$(claude -p "$prompt" \
    --max-turns 8 \
    --permission-mode acceptEdits \
    --permission-prompts none \
    --allowedTools "Read,Glob,Grep,Edit(docs/overseer.md),Edit(.claude/state/force_replan),Edit(.claude/state/cancel),Bash(python3 scripts/budget.py *),Bash(python scripts/budget.py *),Bash(tail *)" \
    --output-format json)"
  exit_code=$?

  printf '%s\n' "$result" > "$S/overseer_last.json"

  is_error="$(printf '%s' "$result" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("true" if d.get("is_error") else "false")
except Exception:
    print("true")
' 2>/dev/null)"
  is_error="${is_error//$'\r'/}"
  [ -z "$is_error" ] && is_error="true"

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$ts overseer tick exit=$exit_code is_error=$is_error" >> "$S/overseer.log"

  [ "$is_error" = "false" ]
}

if [ -n "$LOOP_MIN" ]; then
  while true; do
    do_tick
    last_exit=$?
    if [ ! -f "$S/brief.json" ] || is_terminal_run_state; then
      exit "$last_exit"
    fi
    sleep "$((LOOP_MIN * 60))"
  done
else
  do_tick
  exit $?
fi
