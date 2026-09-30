#!/usr/bin/env bash
# SessionStart hook: re-anchors the mission brief, plan, and flags into context after /compact or resume.
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"
mkdir -p "$CLAUDE_PROJECT_DIR/docs/ledgers" "$CLAUDE_PROJECT_DIR/.claude/state"

sess_json() { printf '{"hook_event_name":"SessionStart","source":"%s","cwd":"%s"}' "$1" "$CLAUDE_PROJECT_DIR"; }

# 1. source startup -> no-op, no output, even though nothing else set up
OUT="$(hook anchor.sh "$(sess_json startup)")"; rc=$?
if [ "$rc" = 0 ] && [ -z "$OUT" ]; then ok "startup: exit 0, empty stdout"; else bad "startup: exit 0, empty stdout (rc=$rc out=$OUT)"; fi

# 2. source compact without brief.json -> no-op
OUT="$(hook anchor.sh "$(sess_json compact)")"; rc=$?
if [ "$rc" = 0 ] && [ -z "$OUT" ]; then ok "compact w/o brief: exit 0, empty stdout"; else bad "compact w/o brief: exit 0, empty stdout (rc=$rc out=$OUT)"; fi

# 3. fixtures: brief.json + task.json (two tasks, one merged one pending; one assumption; one blocked entry)
cat > "$CLAUDE_PROJECT_DIR/.claude/state/brief.json" <<'EOF'
{
  "mission": {"goal": "Add a README that describes quickship", "deliverables": ["README.md"]},
  "success_criteria": [{"kind": "test", "cmd": "bash tests/run.sh", "expect": 0}],
  "budgets": {"tokens": 5000000, "cost_usd": 40, "wall_clock_min": 480, "steps": 400, "stall_limit": 3, "replan_limit": 5, "critic_rounds": 2},
  "permissions": {"irreversible": {"default": "skip-and-record", "allow": ["git push origin mission/*"]}},
  "ambiguity_policy": "choose-default-and-record"
}
EOF

cat > "$CLAUDE_PROJECT_DIR/docs/ledgers/task.json" <<'EOF'
{
  "goal": "Add a README that describes quickship",
  "plan": [
    {"slug": "add-readme", "goal": "Write the README", "owns": ["README.md"], "status": "merged", "branch": "mission/add-readme", "commit": "abc123"},
    {"slug": "wire-ci", "goal": "Wire up CI", "owns": [".github/workflows/ci.yml"], "status": "pending", "branch": "", "commit": ""}
  ],
  "facts": [],
  "assumptions": [{"text": "Node 20 is available in CI", "ts": "2026-09-30T09:00:00Z"}],
  "blocked": [{"step": "s003", "rule": "no direct push to main", "ts": "2026-09-30T09:05:00Z"}],
  "replan_count": 0, "stall_count": 0, "is_complete": false
}
EOF

touch "$CLAUDE_PROJECT_DIR/.claude/state/cancel"

OUT="$(hook anchor.sh "$(sess_json compact)")"; rc=$?
if [ "$rc" = 0 ]; then ok "compact with brief: exit 0"; else bad "compact with brief: exit 0 (rc=$rc out=$OUT)"; fi
parse_err="$(printf '%s' "$OUT" | "$QS_PYTHON" -c 'import json,sys; json.load(sys.stdin)' 2>&1 1>/dev/null)"
if [ -z "$parse_err" ]; then ok "compact with brief: stdout is valid JSON"; else bad "compact with brief: stdout is valid JSON ($parse_err)"; fi
ctx="$(printf '%s' "$OUT" | "$QS_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
expect_contains "context has goal text" "Add a README that describes quickship" "$ctx"
expect_contains "context has mission-brief tag" "<mission-brief>" "$ctx"
expect_contains "context has merged slug+status" "add-readme|merged" "$ctx"
expect_contains "context has pending slug+status" "wire-ci|pending" "$ctx"
expect_contains "context has assumption text" "Node 20 is available in CI" "$ctx"
expect_contains "context has blocked step" "s003" "$ctx"
expect_contains "context has cancel=yes" "cancel=yes" "$ctx"
expect_contains "context has force_replan=no" "force_replan=no" "$ctx"
expect_contains "context has never-ask sentence" "You never ask a question" "$ctx"

# 4. source resume behaves like compact
OUT2="$(hook anchor.sh "$(sess_json resume)")"; rc=$?
if [ "$rc" = 0 ]; then ok "resume: exit 0"; else bad "resume: exit 0 (rc=$rc out=$OUT2)"; fi
ctx2="$(printf '%s' "$OUT2" | "$QS_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
expect_contains "resume context has goal text" "Add a README that describes quickship" "$ctx2"
expect_contains "resume context has never-ask sentence" "You never ask a question" "$ctx2"

# 5. a brief with a 20000-char goal yields additionalContext of at most 9000 characters
big="$("$QS_PYTHON" -c "print('x' * 20000)")"
cat > "$CLAUDE_PROJECT_DIR/.claude/state/brief.json" <<EOF
{"mission": {"goal": "$big", "deliverables": ["README.md"]}, "success_criteria": [], "budgets": {"tokens":1,"cost_usd":1,"wall_clock_min":1,"steps":1,"stall_limit":1,"replan_limit":1,"critic_rounds":1}, "permissions": {"irreversible": {"default": "skip-and-record", "allow": []}}, "ambiguity_policy": "choose-default-and-record"}
EOF
OUT3="$(hook anchor.sh "$(sess_json compact)")"
len="$(printf '%s' "$OUT3" | "$QS_PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(len(d["hookSpecificOutput"]["additionalContext"]))')"
if [ -n "$len" ] && [ "$len" -le 9000 ]; then ok "huge goal: additionalContext <= 9000 chars"; else bad "huge goal: additionalContext <= 9000 chars (got $len)"; fi

# 6. malformed stdin fails closed
expect_exit "malformed stdin fails closed" 2 hook anchor.sh "not json"
expect_exit "empty stdin fails closed" 2 hook anchor.sh ""

finish
