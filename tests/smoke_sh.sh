#!/usr/bin/env bash
# Tests for scripts/smoke.sh
. "$(dirname "$0")/lib.sh"
export SMOKE_BOOT_TIMEOUT=10
run() { ( cd "$1" && bash scripts/smoke.sh ); }

echo "1. clean fixture"
F="$(mkfixture)"
OUT="$(run "$F" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "clean exit $rc: $OUT"
[ "$(printf '%s\n' "$OUT" | tail -n 1)" = "PASS (spec skipped)" ] && ok "final line" || bad "final line: $(printf '%s' "$OUT" | tail -n 2)"

echo "1b. cleanup after case 1"
line="$(printf '%s\n' "$OUT" | grep -m1 '^smoke: pid ')"
pid="$(printf '%s' "$line" | awk '{print $3}')"; port="$(printf '%s' "$line" | awk '{print $5}')"
if [ -n "$pid" ] && [ -n "$port" ]; then
  if kill -0 "$pid" 2>/dev/null; then bad "pid $pid still alive"; else ok "pid gone"; fi
  "$QS_PYTHON" -c 'import socket,sys;s=socket.socket();sys.exit(0 if s.connect_ex(("127.0.0.1",int(sys.argv[1]))) else 1)' "$port" \
    && ok "port $port closed" || bad "port $port still listening"
else bad "no 'smoke: pid <pid> port <port>' line"; fi

echo "2. demo exits during boot"
F="$(mkfixture)"; printf '#!/usr/bin/env bash\nexit 3\n' >"$F/demo.sh"
expect_exit "exit 1" 1 run "$F"
expect_contains "exited during boot" "exited during boot" "$OUT"
expect_contains "log tail" "smoke.log" "$OUT"

echo "3. secret in untracked file"
F="$(mkfixture)"; key="$(printf 'AKIA%s' 1234567890ABCDEF)"; printf 'k=%s\n' "$key" >"$F/leak.txt"
expect_exit "exit 1" 1 run "$F"
expect_contains "mentions secrets" "secrets" "$OUT"
expect_contains "names file" "leak.txt" "$OUT"
case "$OUT" in *"$key"*) bad "key value leaked";; *) ok "key not printed";; esac

echo "4. tracked .env"
F="$(mkfixture)"; echo 'X=1' >"$F/.env"; git -C "$F" add .env; git -C "$F" commit -qm env
expect_exit "exit 1" 1 run "$F"
expect_contains "env file" "env file" "$OUT"

echo "5. TODO stub"
F="$(mkfixture)"; mkdir -p "$F/src"; echo '// TODO: wire up' >"$F/src/app.js"
expect_exit "exit 1" 1 run "$F"
expect_contains "TODO" "TODO" "$OUT"

echo "7. health path honoured"
F="$(mkfixture)"; printf 'run: ./demo.sh\nhealth: /nope\n' >"$F/DEMO_SPEC.md"
SMOKE_BOOT_TIMEOUT=4 expect_exit "exit 1" 1 run "$F"
expect_contains "health" "health" "$OUT"

echo "8. smoke.py"
F="$(mkfixture)"; mkdir -p "$F/tests"; printf 'import sys\nsys.exit(0)\n' >"$F/tests/smoke.py"
OUT="$(run "$F" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "PASS" ] && ok "spec pass" || bad "spec pass rc=$rc: $(printf '%s' "$OUT" | tail -n 2)"
printf 'import sys\nsys.exit(1)\n' >"$F/tests/smoke.py"
expect_exit "spec fail" 1 run "$F"
expect_contains "FAIL line" "smoke: FAIL:" "$OUT"

echo "9. SIGTERM-ignoring child is killed"
F="$(mkfixture)"
{ printf 'import signal\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\n'; cat "$F/server.py"; } >"$F/ign.py"
printf '#!/usr/bin/env bash\n"%s" ign.py &\nwait\n' "$QS_PYTHON" >"$F/demo.sh"
expect_exit "exit 0" 0 run "$F"
line="$(printf '%s\n' "$OUT" | grep -m1 '^smoke: pid ')"
port="$(printf '%s' "$line" | awk '{print $5}')"
if [ -n "$port" ]; then
  "$QS_PYTHON" -c 'import socket,sys;s=socket.socket();sys.exit(0 if s.connect_ex(("127.0.0.1",int(sys.argv[1]))) else 1)' "$port" \
    && ok "port $port closed" || bad "port $port still listening (TERM-ignoring child survived)"
else bad "no 'smoke: pid <pid> port <port>' line"; fi

echo "10. AIza key in untracked file"
F="$(mkfixture)"; key="$(printf 'AIza%035d' 0)"; printf 'k=%s\n' "$key" >"$F/gkey.txt"
expect_exit "exit 1" 1 run "$F"
expect_contains "names file" "gkey.txt" "$OUT"
case "$OUT" in *"$key"*) bad "key value leaked";; *) ok "key not printed";; esac

echo "11. Playwright spec present but Playwright not installed fails"
F="$(mkfixture)"; mkdir -p "$F/tests" "$F/bin"; : >"$F/tests/smoke.spec.ts"
printf '#!/usr/bin/env bash\nexit 1\n' >"$F/bin/npx"; chmod +x "$F/bin/npx"
OUT="$(PATH="$F/bin:$PATH" run "$F" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "exit 1" || bad "exit $rc: $(printf '%s' "$OUT" | tail -n 2)"
expect_contains "names the missing runner" "Playwright is not installed" "$OUT"
case "$OUT" in *"spec skipped"*) bad "must not report spec skipped";; *) ok "no spec-skipped PASS";; esac

echo "12. stub scan: TODO enum value passes, Lorem Ipsum fails"
F="$(mkfixture)"; mkdir -p "$F/src"; echo 'export const STATUS = "TODO";' >"$F/src/status.js"
expect_exit "STATUS=TODO is not a stub" 0 run "$F"
echo 'const copy = "Lorem Ipsum dolor sit amet";' >"$F/src/copy.js"
expect_exit "Lorem Ipsum fails" 1 run "$F"
expect_contains "names file" "copy.js" "$OUT"

finish
