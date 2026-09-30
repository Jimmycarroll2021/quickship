#!/usr/bin/env bash
# PreToolUse/PostToolUse idempotency guard for `git push` and `gh pr|issue|release create`.
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"
S="$CLAUDE_PROJECT_DIR/.claude/state"

# JSON-encode the command so commands containing quotes/newlines still produce valid JSON.
pre_json() {
  local cmd_json
  cmd_json="$(printf '%s' "$1" | "$QS_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' "$cmd_json"
}
post_json() {
  local cmd_json
  cmd_json="$(printf '%s' "$1" | "$QS_PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":%s},"tool_response":{"exit_code":%s}}' "$cmd_json" "$2"
}
# assert_last_line <label> <expected cmd> <expected step> -- checks the most recently
# appended idem.jsonl line has exactly these normalised fields (catches field-shift bugs).
assert_last_line() {
  local label=$1 want_cmd=$2 want_step=$3
  OUT="$("$QS_PYTHON" -c '
import json, sys

path, want_cmd, want_step = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    lines = [l for l in f if l.strip()]
last = json.loads(lines[-1])
if last.get("cmd") == want_cmd and last.get("step") == want_step:
    print("OK")
else:
    print("MISMATCH cmd=%r step=%r" % (last.get("cmd"), last.get("step")))
' "$S/idem.jsonl" "$want_cmd" "$want_step" 2>&1)"
  case "$OUT" in
    OK) ok "$label" ;;
    *) bad "$label ($OUT)" ;;
  esac
}

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

# --- regression cases: only a subcommand that itself STARTS WITH the target, and text
# inside quotes never triggers a match (bug a); ledger fields never shift (bug b). ---

# the exact bad case from the live run: "git push" and "gh pr create" only appear inside
# a quoted argument to a ledger-append call, so this must not match at all.
ledger_before="$(wc -l < "$S/idem.jsonl" 2>/dev/null || echo 0)"
expect_exit "quoted git push/gh pr create text inside another command does not match" 0 \
  hook idem.sh "$(pre_json 'python scripts/ledger.py append blocked lead "combined git push and gh pr create denied ..."')"
ledger_after="$(wc -l < "$S/idem.jsonl" 2>/dev/null || echo 0)"
[ "$ledger_before" = "$ledger_after" ] && ok "ledger not appended for quoted-text command" || bad "ledger appended for quoted-text command (before=$ledger_before after=$ledger_after)"

# a leading "cd <dir> &&" is its own subcommand; the push subcommand after it still matches,
# and the ledger records the normalised push subcommand, not the whole line.
printf '{"id":"s009"}' > "$S/current_step.json"
expect_exit "cd-prefixed git push matches" 0 hook idem.sh "$(pre_json 'cd .claude/worktrees/x && git push origin mission/x')"
assert_last_line "cd-prefixed push pending line normalises to the push subcommand" "git push origin mission/x" "s009"
expect_exit "cd-prefixed git push post recorded" 0 hook idem.sh "$(post_json 'cd .claude/worktrees/x && git push origin mission/x' 0)"
assert_last_line "cd-prefixed push done line normalises to the push subcommand" "git push origin mission/x" "s009"
expect_exit "cd-prefixed git push repeat denied" 2 hook idem.sh "$(pre_json 'cd .claude/worktrees/x && git push origin mission/x')"
expect_contains "cd-prefixed push denial mentions already executed" "already executed" "$OUT"

# git -C <dir> push is recognised as a push subcommand too.
printf '{"id":"s010"}' > "$S/current_step.json"
expect_exit "git -C <dir> push matches" 0 hook idem.sh "$(pre_json 'git -C .claude/worktrees/x push origin mission/x')"
assert_last_line "git -C push pending line is the full push subcommand" "git -C .claude/worktrees/x push origin mission/x" "s010"

# a command containing a real newline, with "gh pr create" only inside a quoted string,
# must not match -- quoting, not the presence of a newline, decides.
multiline_cmd=$'echo "gh pr create fake\nstill quoted" && npm test'
ledger_before="$(wc -l < "$S/idem.jsonl" 2>/dev/null || echo 0)"
expect_exit "quoted gh pr create spanning a newline does not match" 0 hook idem.sh "$(pre_json "$multiline_cmd")"
ledger_after="$(wc -l < "$S/idem.jsonl" 2>/dev/null || echo 0)"
[ "$ledger_before" = "$ledger_after" ] && ok "ledger not appended for newline/quoted command" || bad "ledger appended for newline/quoted command (before=$ledger_before after=$ledger_after)"

# after every match above, no ledger line ever has its cmd/step fields shifted: cmd must
# look like the matched subcommand it came from, and must never equal the step id.
OUT="$("$QS_PYTHON" -c '
import json, re, sys

path = sys.argv[1]
pattern = re.compile(r"^(git push\b|git -C \S+ push\b|gh (pr|issue|release) create\b)")
bad_lines = []
with open(path, encoding="utf-8") as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        cmd = obj.get("cmd", "")
        step = obj.get("step", "")
        if cmd == step:
            bad_lines.append("line %d: cmd equals step (%r)" % (i, cmd))
        elif not pattern.match(cmd):
            bad_lines.append("line %d: cmd does not look like a matched subcommand: %r" % (i, cmd))
if bad_lines:
    print("BAD " + "; ".join(bad_lines))
else:
    print("OK")
' "$S/idem.jsonl" 2>&1)"
case "$OUT" in
  OK) ok "every ledger line cmd is the matched subcommand, never the step id" ;;
  *) bad "ledger field-shift check ($OUT)" ;;
esac

finish
