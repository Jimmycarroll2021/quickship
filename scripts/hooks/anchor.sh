#!/usr/bin/env bash
# SessionStart hook. After /compact or a resume, re-injects the mission brief, plan, assumptions,
# blocked items, budget summary and control flags into context so the lead loop can pick up cleanly.
# Input: hook JSON on stdin. Fails closed: malformed input -> exit 2. No active run -> exit 0, no output.
set -u
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
in="$(cat)"
source_val="$(printf '%s' "$in" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("source", ""))
' 2>/dev/null)" || { echo "anchor: malformed hook input" >&2; exit 2; }
source_val="${source_val//$'\r'/}"   # python on Windows emits CRLF
case "$source_val" in
  compact|resume) ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
S="$ROOT/.claude/state"
[ -f "$S/brief.json" ] || exit 0

budget_line="budget: unavailable"
if [ -f "$ROOT/scripts/budget.py" ]; then
  b_out="$("$PY" "$ROOT/scripts/budget.py" 2>/dev/null)"
  b_rc=$?
  b_out="${b_out//$'\r'/}"
  first_line="${b_out%%$'\n'*}"
  if [ "$b_rc" = 0 ] && [ -n "$first_line" ]; then
    budget_line="budget: $first_line"
  fi
fi

cancel_flag="no"; [ -f "$S/cancel" ] && cancel_flag="yes"
replan_flag="no"; [ -f "$S/force_replan" ] && replan_flag="yes"

"$PY" - "$ROOT" "$budget_line" "$cancel_flag" "$replan_flag" <<'PYEOF'
import json
import os
import sys

root, budget_line, cancel_flag, replan_flag = sys.argv[1:5]
state_dir = os.path.join(root, ".claude", "state")
brief_path = os.path.join(state_dir, "brief.json")
task_path = os.path.join(root, "docs", "ledgers", "task.json")


def build():
    with open(brief_path, "r", encoding="utf-8") as f:
        brief = json.load(f)

    lines = []
    mission = brief.get("mission", {})
    lines.append("<mission-brief>")
    lines.append("goal: {}".format(mission.get("goal", "")))
    lines.append("deliverables:")
    for d in mission.get("deliverables", []):
        lines.append("- {}".format(d))
    lines.append("success_criteria:")
    for c in brief.get("success_criteria", []):
        kind = c.get("kind", "")
        rest = ", ".join("{}={}".format(k, v) for k, v in c.items() if k != "kind")
        lines.append("- {}: {}".format(kind, rest))
    budgets = brief.get("budgets", {})
    lines.append("budgets: " + " ".join("{}={}".format(k, v) for k, v in budgets.items()))
    perms = brief.get("permissions", {}).get("irreversible", {})
    lines.append("permissions: default={} allow={}".format(perms.get("default", ""), perms.get("allow", [])))
    lines.append("ambiguity_policy: {}".format(brief.get("ambiguity_policy", "")))
    lines.append("</mission-brief>")
    lines.append("")

    if os.path.isfile(task_path):
        try:
            with open(task_path, "r", encoding="utf-8") as f:
                task = json.load(f)
        except Exception:
            task = {}

        lines.append("<plan>")
        lines.append("slug|status|goal")
        for t in task.get("plan", []):
            lines.append("{}|{}|{}".format(t.get("slug", ""), t.get("status", ""), t.get("goal", "")))
        lines.append("</plan>")
        lines.append("")

        lines.append("<assumptions>")
        for a in task.get("assumptions", []):
            lines.append("- {} ({})".format(a.get("text", ""), a.get("ts", "")))
        lines.append("</assumptions>")
        lines.append("")

        lines.append("<blocked>")
        for b in task.get("blocked", []):
            lines.append("- {}: {} ({})".format(b.get("step", ""), b.get("rule", ""), b.get("ts", "")))
        lines.append("</blocked>")
        lines.append("")
    else:
        lines.append("plan: none yet")
        lines.append("")

    lines.append(budget_line)
    lines.append("flags: cancel={} force_replan={}".format(cancel_flag, replan_flag))
    lines.append("")
    lines.append("You never ask a question. Continue the lead loop in CLAUDE.md from step 1.")

    text = "\n".join(lines)
    return text[:9000]


try:
    context_text = build()
except Exception as exc:
    print("anchor: failed to build context: {}".format(exc), file=sys.stderr)
    sys.exit(2)

out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context_text}}
print(json.dumps(out))
PYEOF
