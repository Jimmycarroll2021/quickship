#!/usr/bin/env bash
# Budget hook (PreToolUse + PostToolUse, matcher .*). Contract: docs/design/contracts.md "Budgets".
# No-op without an active run. PostToolUse: count the step and report usage as additionalContext.
# PreToolUse: once any budget is exhausted, allow only reads and the final REPORT.md / RUN_STATE writes.
# Fails closed: malformed input -> exit 2.
set -u
[ "${QS_ROLE:-lead}" = overseer ] && exit 0   # overseer tool calls are neither gated nor counted as steps
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
S="$ROOT/.claude/state"
[ -f "$S/brief.json" ] || exit 0   # runs on every tool call: leave fast when no run is active
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
BUDGET_PY="$(cd "$(dirname "$0")/.." && pwd)/budget.py"
in="$(cat)"
parsed="$(printf '%s' "$in" | "$PY" -c '
import json, sys
d = json.load(sys.stdin); e = d["hook_event_name"]; t = d["tool_name"]; i = d.get("tool_input") or {}
fp = i.get("file_path", "") if isinstance(i, dict) else ""
for v in (e, t, str(fp).replace("\\", "/"), d.get("transcript_path") or ""): print(str(v).replace("\n", " "))
' 2>/dev/null)" || { echo "budget: malformed hook input, denied" >&2; exit 2; }
parsed="${parsed//$'\r'/}"   # python on Windows emits CRLF
{ IFS= read -r event; IFS= read -r tool; IFS= read -r fpath; IFS= read -r transcript; } <<< "$parsed"
targs=(); [ -n "$transcript" ] && targs=(--transcript "$transcript")

# remember the transcript path (only the hook is ever told it) so budget.py can find it without --transcript
if [ -n "$transcript" ]; then
  cur="$(cat "$S/transcript_path" 2>/dev/null)"
  if [ "$cur" != "$transcript" ]; then
    printf '%s' "$transcript" > "$S/transcript_path.tmp" && mv -f "$S/transcript_path.tmp" "$S/transcript_path"
  fi
fi

case "$event" in
  PostToolUse)
    n="$(tr -dc '0-9' 2>/dev/null < "$S/steps")"; n=$(( ${n:-0} + 1 ))
    printf '%s\n' "$n" > "$S/steps.tmp" && mv -f "$S/steps.tmp" "$S/steps"
    "$PY" "$BUDGET_PY" "${targs[@]}" 2>/dev/null | "$PY" -c '
import json, sys
b = json.load(sys.stdin); L = b["limits"]
n = lambda v: ("%d" % v) if float(v).is_integer() else ("%g" % v)
ctx = "BUDGET tokens=%d/%s cost=%.2f/%s min=%.1f/%s steps=%d/%s" % (
    b["tokens"], n(L["tokens"]), b["cost_usd"], n(L["cost_usd"]),
    b["elapsed_min"], n(L["wall_clock_min"]), b["steps"], n(L["steps"]))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ctx}}))
' 2>/dev/null
    exit 0
    ;;
  PreToolUse)
    case "$tool" in Read|Glob|Grep) exit 0;; esac
    ex="$("$PY" "$BUDGET_PY" --exhausted-only "${targs[@]}")" || { echo "budget: cannot read budget state, denied" >&2; exit 2; }
    ex="${ex//$'\r'/}"; ex="${ex%%$'\n'*}"
    [ -z "$ex" ] && exit 0
    if [[ "$tool" == Write || "$tool" == Edit ]] && [[ "$fpath" =~ (^|/)docs/(REPORT\.md|RUN_STATE)$ ]]; then exit 0; fi
    echo "budget exhausted ($ex): write docs/RUN_STATE {\"state\":\"DONE_PARTIAL\"} and docs/REPORT.md, then stop" >&2
    exit 2
    ;;
esac
exit 0
