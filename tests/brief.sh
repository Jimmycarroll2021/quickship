#!/usr/bin/env bash
# scripts/brief.py: BRIEF.yaml -> .claude/state/brief.json (validate) and show.
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"
BRIEF="$ROOT/BRIEF.example.yaml"
SJSON="$CLAUDE_PROJECT_DIR/.claude/state/brief.json"
STARTED="$CLAUDE_PROJECT_DIR/.claude/state/started_at"

py() { "$QS_PYTHON" "$ROOT/scripts/brief.py" "$@"; }

# --- example validates ---
expect_exit "example validates" 0 py validate --brief "$BRIEF"
expect_exit "brief.json written" 0 test -f "$SJSON"
expect_exit "started_at written" 0 test -f "$STARTED"

brief_content="$(cat "$SJSON")"
expect_contains "brief.json has goal" "Add a README" "$brief_content"

ncrit="$(grep -o '"kind":' "$SJSON" | wc -l | tr -d ' ')"
expect_contains "brief.json has 4 criteria" "4" "$ncrit"

expect_contains "budgets.stall_limit=3" '"stall_limit": 3' "$brief_content"

# --- started_at not overwritten on second validate ---
first_started="$(cat "$STARTED")"
sleep 1
expect_exit "second validate ok" 0 py validate --brief "$BRIEF"
second_started="$(cat "$STARTED")"
expect_contains "started_at unchanged" "$first_started" "$second_started"

# --- show prints the goal ---
expect_exit "show runs" 0 py show
expect_contains "show prints goal" "Add a README" "$OUT"

# --- missing budgets.steps -> exit 2, stderr names it ---
BAD1="$CLAUDE_PROJECT_DIR/bad1.yaml"
sed '/^  steps:/d' "$BRIEF" > "$BAD1"
expect_exit "missing budgets.steps -> exit 2" 2 py validate --brief "$BAD1"
expect_contains "stderr names budgets.steps" "budgets.steps" "$OUT"

# --- budgets.tokens: 0 -> exit 2 ---
BAD2="$CLAUDE_PROJECT_DIR/bad2.yaml"
sed 's/^  tokens: .*/  tokens: 0/' "$BRIEF" > "$BAD2"
expect_exit "budgets.tokens=0 -> exit 2" 2 py validate --brief "$BAD2"
expect_contains "stderr names budgets.tokens" "budgets.tokens" "$OUT"

# --- unknown kind -> exit 2 ---
BAD3="$CLAUDE_PROJECT_DIR/bad3.yaml"
sed 's/{kind: test, cmd: "bash tests\/run.sh", expect: 0}/{kind: bogus, cmd: "x", expect: 0}/' "$BRIEF" > "$BAD3"
expect_exit "unknown kind -> exit 2" 2 py validate --brief "$BAD3"

# --- built-in reader forced via QS_NO_YAML=1 matches PyYAML path (when both available) ---
rm -f "$SJSON" "$STARTED"
expect_exit "validate with PyYAML/default reader" 0 py validate --brief "$BRIEF"
cp "$SJSON" "$CLAUDE_PROJECT_DIR/brief_default.json"

rm -f "$SJSON" "$STARTED"
expect_exit "validate with QS_NO_YAML=1 (built-in reader)" 0 env QS_NO_YAML=1 "$QS_PYTHON" "$ROOT/scripts/brief.py" validate --brief "$BRIEF"
cp "$SJSON" "$CLAUDE_PROJECT_DIR/brief_builtin.json"

d1="$(cat "$CLAUDE_PROJECT_DIR/brief_default.json")"
d2="$(cat "$CLAUDE_PROJECT_DIR/brief_builtin.json")"
d1="${d1//$'\r'/}"; d2="${d2//$'\r'/}"
if [ "$d1" = "$d2" ]; then ok "built-in reader output matches default reader"; else bad "built-in reader output differs from default reader"; fi

# --- built-in reader: trailing comments are dropped, a # inside quotes is kept ---
CMT="$CLAUDE_PROJECT_DIR/comments.yaml"
sed -e 's/^  steps: .*/  steps: 400   # every tool call counts/' \
    -e 's/^  cost_usd: .*/  cost_usd: 40 #no space before text/' \
    -e 's/^  goal: .*/  goal: "Ship issue #7 to prod"/' "$BRIEF" > "$CMT"
rm -f "$SJSON" "$STARTED"
expect_exit "built-in reader: trailing comment after a number" 0 env QS_NO_YAML=1 "$QS_PYTHON" "$ROOT/scripts/brief.py" validate --brief "$CMT"
c="$(cat "$SJSON" 2>/dev/null)"
expect_contains "built-in reader: steps parsed as 400" '"steps": 400' "$c"
expect_contains "built-in reader: cost_usd parsed as 40" '"cost_usd": 40' "$c"
expect_contains "built-in reader: # inside quotes kept" 'issue #7' "$c"

finish
