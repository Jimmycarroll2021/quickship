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
  fail) echo "line one"; echo 'say "quoted" \ back'; echo "line three"; echo FAIL; exit 1;;
  esc) printf '\033[31mred FAIL\033[0m\n'; exit 1;;
  oneline) printf 'one "quoted" line'; exit 1;;
esac
SM
echo pass > "$F/MODE"
run() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$F" bash "$ROOT/scripts/stop_hook.sh"; }
isjson() { printf '%s' "$1" | "$QS_PYTHON" -m json.tool >/dev/null 2>&1; }

OUT="$(run '{"stop_hook_active":false}')"; rc=$?
[ $rc = 0 ] && [ -z "$OUT" ] && ok "1 no DEMO_SPEC.md: silent exit 0" || bad "1 no DEMO_SPEC.md (rc=$rc out=$OUT)"

: > "$F/DEMO_SPEC.md"; : > "$F/demo.sh"
OUT="$(run '{"stop_hook_active":false}')"; rc=$?
[ $rc = 0 ] && [ -z "$OUT" ] && ok "2 smoke passes: silent exit 0" || bad "2 smoke passes (rc=$rc out=$OUT)"

echo fail > "$F/MODE"
OUT="$(run '{"stop_hook_active":false}')"; rc=$?
[ $rc = 0 ] && ok "3 fail: exit 0" || bad "3 fail: exit $rc"
expect_contains "3 fail: decision block" '"decision":"block"' "$OUT"
expect_contains "3 fail: reason has FAIL" 'FAIL' "$OUT"
isjson "$OUT" && ok "3 fail: valid JSON" || bad "3 fail: invalid JSON: $OUT"
expect_contains "3 fail: quote preserved" 'quoted' "$OUT"

OUT="$(run '{"stop_hook_active": true}')"; rc=$?
[ $rc = 0 ] && ok "4 active: exit 0" || bad "4 active: exit $rc"
expect_contains "4 active: systemMessage" 'systemMessage' "$OUT"
isjson "$OUT" && ok "4 active: valid JSON" || bad "4 active: invalid JSON: $OUT"

echo esc > "$F/MODE"
OUT="$(run '{"stop_hook_active":false}')"
isjson "$OUT" && ok "5 ESC in output: valid JSON" || bad "5 ESC: invalid JSON: $OUT"
expect_contains "5 ESC: text kept" '[31m' "$OUT"

echo oneline > "$F/MODE"
OUT="$(run '{"stop_hook_active":false}')"
isjson "$OUT" && ok "6 one-line log with quote: valid JSON" || bad "6 one-line: invalid JSON: $OUT"
expect_contains "6 one-line: blocks" '"decision":"block"' "$OUT"
finish
