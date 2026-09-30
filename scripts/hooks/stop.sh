#!/usr/bin/env bash
# Stop hook. No active run (no brief.json) -> just run the quality gate. Active run -> require a
# terminal docs/RUN_STATE before the gate runs: block twice with a reminder, then force SAFE_STOP on
# the 3rd stop attempt so an unattended run can never hang open. RUN_STATE HALT skips the gate entirely.
# Input: hook JSON on stdin (fails closed: malformed -> exit 2). Exit 0 = allow stop, exit 2 = block.
set -u
# The overseer runs its own claude -p session in this repo; it must never block or decide the mission state.
[ "${QS_ROLE:-lead}" = overseer ] && exit 0
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
in="$(cat)"
printf '%s' "$in" | "$PY" -c 'import json, sys; json.load(sys.stdin)' >/dev/null 2>&1 \
  || { echo "stop: malformed hook input, denied" >&2; exit 2; }

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || { echo "stop: cannot resolve project root" >&2; exit 2; }
S="$ROOT/.claude/state"

# No active run: nothing to gate on RUN_STATE, just run the quality gate.
[ -f "$S/brief.json" ] || exec bash "$ROOT/scripts/gate.sh"

state=""
if [ -f "$ROOT/docs/RUN_STATE" ]; then
  state="$("$PY" -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print(d.get("state", ""))
except Exception:
    print("")
' "$ROOT/docs/RUN_STATE" 2>/dev/null)"
  state="${state//$'\r'/}"
fi

case "$state" in
  DONE|DONE_PARTIAL|SAFE_STOP)
    ;; # terminal: fall through to the gate
  HALT)
    exit 0
    ;;
  *)
    mkdir -p "$S" 2>/dev/null
    n="$(cat "$S/stop_attempts" 2>/dev/null)"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    n=$((n + 1))
    printf '%s' "$n" > "$S/stop_attempts"
    if [ "$n" -lt 3 ]; then
      echo "no terminal RUN_STATE: write docs/RUN_STATE and docs/REPORT.md before stopping" >&2
      exit 2
    fi
    mkdir -p "$ROOT/docs" 2>/dev/null
    at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"state":"SAFE_STOP","reason":"lead ended without terminal state","at":"%s"}\n' "$at" > "$ROOT/docs/RUN_STATE"
    ;;
esac

exec bash "$ROOT/scripts/gate.sh"
