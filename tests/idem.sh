#!/usr/bin/env bash
# PreToolUse/PostToolUse idempotency guard for `git push` and `gh pr|issue|release create`.
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"
S="$CLAUDE_PROJECT_DIR/.claude/state"

pre_json()  { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
post_json() { printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"exit_code":%s}}' "$1" "$2"; }

# non-matching command is a pure no-op, no ledger created
expect_exit "non-matching command allowed" 0 hook idem.sh "$(pre_json "npm test")"
[ -f "$S/idem.jsonl" ] && bad "idem.jsonl created for non-matching command" || ok "idem.jsonl not created for non-matching command"

# matching command with a current step: PreToolUse allows and records pending
printf '{"id":"s007"}' > "$S/current_step.json"
expect_exit "first gh pr create allowed" 0 hook idem.sh "$(pre_json "gh pr create --title x")"
expect_contains "pending line has step s007" '"step": "s007"' "$(cat "$S/idem.jsonl")"
expect_contains "pending line has status pending" '"status": "pending"' "$(cat "$S/idem.jsonl")"

# PostToolUse records the done outcome
expect_exit "PostToolUse allowed" 0 hook idem.sh "$(post_json "gh pr create --title x" 0)"
expect_contains "done line recorded" '"status": "done"' "$(cat "$S/idem.jsonl")"

# repeat PreToolUse for the same key is denied
expect_exit "repeat gh pr create denied" 2 hook idem.sh "$(pre_json "gh pr create --title x")"
expect_contains "denial mentions already executed" "already executed" "$OUT"

# extra whitespace normalises to the same key, still denied
expect_exit "extra-space repeat denied" 2 hook idem.sh "$(pre_json "gh  pr   create --title x")"
expect_contains "denial mentions already executed (normalised)" "already executed" "$OUT"

# a new step id changes the key, so it's allowed again
printf '{"id":"s008"}' > "$S/current_step.json"
expect_exit "new step id allowed" 0 hook idem.sh "$(pre_json "gh pr create --title x")"

# git push behaves the same way; also covers no current_step.json -> "nostep"
rm -f "$S/current_step.json"
expect_exit "git push first allowed" 0 hook idem.sh "$(pre_json "git push origin mission/x")"
expect_exit "git push post allowed" 0 hook idem.sh "$(post_json "git push origin mission/x" 0)"
expect_exit "git push repeat denied" 2 hook idem.sh "$(pre_json "git push origin mission/x")"
expect_contains "git push denial mentions already executed" "already executed" "$OUT"
expect_contains "nostep used when current_step.json is absent" '"step": "nostep"' "$(cat "$S/idem.jsonl")"

# fail closed on malformed input
expect_exit "garbage stdin fails closed" 2 hook idem.sh "not json"
expect_exit "empty stdin fails closed" 2 hook idem.sh ""

finish
