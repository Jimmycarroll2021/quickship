#!/usr/bin/env bash
# Tests scripts/stop_hook.sh against a fixture repo with a fake scripts/smoke.sh.
. "$(dirname "$0")/lib.sh"
echo "stop_hook.sh"
F="$(tmpdir)"; trap 'rm -rf "$F"' EXIT
git init -q "$F"; mkdir -p "$F/scripts"
cat > "$F/scripts/smoke.sh" <<'SM'
#!/usr/bin/env bash
case "$(cat "$(dirname "$0")/../MODE")" in
  pass) echo PASS; exit 0;;
  fail) echo "line one"; echo 'say "quoted" \ back'; printf '\033[31mred\033[0m\n'; echo FAIL; exit 1;;
  silent) exit 1;;
esac
SM
echo pass > "$F/MODE"
# run <stdin-json>: stdout in $OUT, stderr in $ERR, exit code in $rc
run() {
  local e; e="$(mktemp "${TMPDIR:-/tmp}/qs-hook-err.XXXXXX")"
  OUT="$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$F" bash "$ROOT/scripts/stop_hook.sh" 2>"$e")"; rc=$?
  ERR="$(cat "$e")"; rm -f "$e"
}
isjson() { printf '%s' "$1" | "$QS_PYTHON" -m json.tool >/dev/null 2>&1; }

run '{"stop_hook_active":false}'
[ $rc = 0 ] && [ -z "$OUT$ERR" ] && ok "1 no DEMO_SPEC.md: silent exit 0" || bad "1 no DEMO_SPEC.md (rc=$rc out=$OUT err=$ERR)"

: > "$F/DEMO_SPEC.md"; : > "$F/demo.sh"
run '{"stop_hook_active":false}'
[ $rc = 0 ] && [ -z "$OUT$ERR" ] && ok "2 smoke passes: silent exit 0" || bad "2 smoke passes (rc=$rc out=$OUT err=$ERR)"

echo fail > "$F/MODE"
run '{"stop_hook_active":false}'
[ $rc = 2 ] && ok "3 fail: exit 2 blocks the stop" || bad "3 fail: exit $rc"
[ -z "$OUT" ] && ok "3 fail: nothing on stdout" || bad "3 fail: stdout not empty: $OUT"
expect_contains "3 fail: reason on stderr has FAIL" 'FAIL' "$ERR"
expect_contains "3 fail: quotes and backslashes survive" 'say "quoted" \ back' "$ERR"
expect_contains "3 fail: colour codes pass through" '[31m' "$ERR"
expect_contains "3 fail: says fix the cause" 'fix the cause' "$ERR"

run '{"stop_hook_active": true}'
[ $rc = 0 ] && ok "4 active+failing: exit 0 lets go" || bad "4 active+failing: exit $rc"
expect_contains "4 active+failing: systemMessage" 'systemMessage' "$OUT"
isjson "$OUT" && ok "4 active+failing: valid JSON" || bad "4 active+failing: invalid JSON: $OUT"

echo pass > "$F/MODE"
run '{"stop_hook_active": true}'
[ $rc = 0 ] && [ -z "$OUT$ERR" ] && ok "4b active+passing: silent exit 0 (no false 'still failing')" || bad "4b active+passing (rc=$rc out=$OUT err=$ERR)"

echo silent > "$F/MODE"
run '{"stop_hook_active":false}'
[ $rc = 2 ] && ok "5 no-output failure: still blocks" || bad "5 no-output: exit $rc"
expect_contains "5 no-output failure: reason filled" 'no output' "$ERR"
finish
