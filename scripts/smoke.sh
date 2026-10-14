#!/usr/bin/env bash
# smoke.sh - the only quickship component allowed to say PASS.
# Scans for secrets and stubs, boots ./demo.sh, waits for the health path, runs the smoke spec if any.
# Final stdout line: PASS | PASS (spec skipped) | FAIL. Exit 0 on PASS, 1 on FAIL. Never invokes claude.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "smoke: FAIL: not a git repository"; echo FAIL; exit 1; }
cd "$ROOT" || exit 1

PY="$(command -v python3 || command -v python || true)"
FAILS=()
SKIPPED=0
PID=""; MODE=""
fail() { FAILS+=("$1"); }
finish_run() {
  local f
  if [ "${#FAILS[@]}" -gt 0 ]; then
    for f in "${FAILS[@]}"; do echo "smoke: FAIL: $f"; done
    echo FAIL; exit 1
  fi
  if [ "$SKIPPED" = 1 ]; then echo "PASS (spec skipped)"; else echo PASS; fi
  exit 0
}

# ---- 1. secret scan ---------------------------------------------------------
SECRET_RE='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|sk-(ant-|proj-)[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{48}|sk_live_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
while IFS= read -r -d '' name; do
  case "${name##*/}" in
    *.example|*.sample|*.template) ;;
    .env|.env.*) fail "secrets: env file: $name";;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)
while IFS= read -r -d '' name; do fail "secrets: possible credential in: $name"; done \
  < <(git grep -lIzE --untracked -e "$SECRET_RE" -- . ':!scripts/smoke.sh' ':!.claude/smoke.log' 2>/dev/null)

# ---- 2. stub scan -----------------------------------------------------------
EXTRA=()
# shellcheck disable=SC2206
[ -n "${SMOKE_STUB_EXCLUDE:-}" ] && for p in $SMOKE_STUB_EXCLUDE; do EXTRA+=(":!$p"); done
STUBS="$(git grep -nIiE --untracked '(//|#|/\*|\*|<!--|--)[[:space:]]*(TODO|FIXME)\b|coming soon|href="#"|not implemented|lorem ipsum' -- . ':!tests' ':!*.md' ':!docs' ':!scripts/smoke.sh' ':!.claude' ${EXTRA[@]+"${EXTRA[@]}"} 2>/dev/null)"
if [ -n "$STUBS" ]; then
  fail "stubs found (TODO/FIXME/placeholder):"
  while IFS= read -r l; do FAILS+=("  $l"); done <<<"$STUBS"
fi

# ---- 3. boot ----------------------------------------------------------------
[ -x ./demo.sh ] || fail "missing or non-executable ./demo.sh"
[ -f DEMO_SPEC.md ] || fail "missing DEMO_SPEC.md"
[ "${#FAILS[@]}" -gt 0 ] && finish_run

HEALTH="$(sed -nE 's/^health:[[:space:]]*([^[:space:]]+).*/\1/p' DEMO_SPEC.md | head -n 1 | tr -d "\`\"'")"
HEALTH="${HEALTH:-/}"
if [ -z "${PORT:-}" ]; then
  [ -n "$PY" ] || { fail "PORT not set and python not available to pick a free port"; finish_run; }
  PORT="$("$PY" -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1]);s.close()')"
fi
export PORT
mkdir -p .claude
LOG=".claude/smoke.log"

alive() { kill -0 "$PID" 2>/dev/null; }
# group_alive: any process left in the demo's process group (MODE=group), else just the leader.
group_alive() {
  if [ "$MODE" = group ]; then kill -0 -- "-$PID" 2>/dev/null; else alive; fi
}
cleanup() {
  local winpid i=0
  trap - EXIT INT TERM
  if [ -n "$PID" ]; then
    case "$MODE" in
      winpid)
        # exec inside demo.sh changes the Windows PID, so resolve it now, not at spawn
        winpid="$(ps -p "$PID" -W 2>/dev/null | awk 'NR==2{print $4}')"
        if [ -n "$winpid" ]; then taskkill //PID "$winpid" //T //F >/dev/null 2>&1; else kill -KILL "$PID" 2>/dev/null; fi ;;
      *) kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null
         while group_alive && [ $i -lt 6 ]; do sleep 0.5; i=$((i+1)); done
         if group_alive; then kill -KILL -- "-$PID" 2>/dev/null || kill -KILL "$PID" 2>/dev/null; fi ;;
    esac
    wait "$PID" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1;; *) WINDOWS=0;; esac
if [ "$WINDOWS" = 0 ] && command -v setsid >/dev/null 2>&1; then
  MODE=group; setsid ./demo.sh >"$LOG" 2>&1 &
  PID=$!
elif [ "$WINDOWS" = 0 ] && [ -n "$PY" ]; then
  MODE=group; "$PY" -c 'import os,sys;os.setsid();os.execvp(sys.argv[1],sys.argv[1:])' ./demo.sh >"$LOG" 2>&1 &
  PID=$!
else
  ./demo.sh >"$LOG" 2>&1 &
  PID=$!
  if command -v taskkill >/dev/null 2>&1; then MODE=winpid
  else MODE=single; echo "smoke: notice: no setsid/python; cleanup can only kill the demo.sh process itself"; fi
fi
echo "smoke: pid $PID port $PORT"

# ---- 4. health wait ---------------------------------------------------------
URL="http://localhost:$PORT$HEALTH"
probe() {
  if command -v curl >/dev/null 2>&1; then curl -fsS --max-time 2 -o /dev/null "$URL" >/dev/null 2>&1
  else "$PY" -c 'import sys,urllib.request;urllib.request.urlopen(sys.argv[1],timeout=2)' "$URL" >/dev/null 2>&1; fi
}
taillog() { echo "--- tail of $LOG ---"; tail -n 40 "$LOG" 2>/dev/null; }
TIMEOUT="${SMOKE_BOOT_TIMEOUT:-60}"
deadline=$(( SECONDS + TIMEOUT ))
healthy=0
while :; do
  if ! alive; then
    fail "demo.sh exited during boot"; taillog; break
  fi
  if probe; then healthy=1; break; fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "health check $URL not ready after ${TIMEOUT}s"; taillog; break
  fi
  sleep 0.5
done
# ---- 5. spec ----------------------------------------------------------------
if [ "$healthy" = 1 ]; then
  if [ -f tests/smoke.spec.ts ]; then
    if npx --no-install playwright --version >/dev/null 2>&1; then
      DEMO_URL="http://localhost:$PORT" npx --no-install playwright test tests/smoke.spec.ts || fail "smoke spec failed: tests/smoke.spec.ts"
    else
      fail "tests/smoke.spec.ts present but Playwright is not installed (npx --no-install playwright); demo.sh must install it"
    fi
  elif [ -f tests/smoke.py ]; then
    if [ -n "$PY" ]; then
      DEMO_URL="http://localhost:$PORT" "$PY" tests/smoke.py || fail "smoke spec failed: tests/smoke.py"
    else
      fail "python not available for tests/smoke.py"
    fi
  else
    echo "SKIP: no smoke spec"; SKIPPED=1
  fi
fi

cleanup
finish_run
