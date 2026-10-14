#!/usr/bin/env bash
# smoke.sh - the only quickship component allowed to say PASS.
# Scans for secrets and stubs, boots ./demo.sh, waits for the health path, runs the smoke spec if any.
# Final stdout line: PASS | PASS (spec skipped) | FAIL. Exit 0 on PASS, 1 on FAIL. Never invokes claude.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "smoke: FAIL: not a git repository"; echo FAIL; exit 1; }
cd "$ROOT" || exit 1

PY="$(command -v python3 || command -v python || true)"
FAILS=()
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
SKIPPED=0
PID=""; WINPID=""; MODE=""

# ---- 1. secret scan ---------------------------------------------------------
SECRET_RE='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|sk-(ant-|proj-)[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
while IFS= read -r -d '' name; do
  [ "$name" = "scripts/smoke.sh" ] && continue
  case "$name" in .claude/smoke.log) continue;; esac
  base="${name##*/}"
  case "$base" in
    .env|.env.*)
      case "$base" in *.example|*.sample|*.template) ;; *) fail "secrets: env file: $name";; esac;;
  esac
  [ -f "$name" ] || continue
  if grep -IqE -e "$SECRET_RE" -- "$name" 2>/dev/null; then fail "secrets: possible credential in: $name"; fi
done < <(git ls-files -z --cached --others --exclude-standard)

# ---- 2. stub scan -----------------------------------------------------------
EXTRA=()
# shellcheck disable=SC2206
[ -n "${SMOKE_STUB_EXCLUDE:-}" ] && for p in $SMOKE_STUB_EXCLUDE; do EXTRA+=(":!$p"); done
STUBS="$(git grep -nIE --untracked "TODO|FIXME|Coming soon|href=\"#\"|Not implemented|lorem ipsum" -- . ':!tests' ':!*.md' ':!docs' ':!scripts/smoke.sh' ':!.claude' "${EXTRA[@]}" 2>/dev/null)"
if [ -n "$STUBS" ]; then
  fail "stubs found (TODO/FIXME/placeholder):"
  while IFS= read -r l; do FAILS+=("  $l"); done <<<"$STUBS"
fi

# ---- 3. boot ----------------------------------------------------------------
[ -x ./demo.sh ] || fail "missing or non-executable ./demo.sh"
[ -f DEMO_SPEC.md ] || fail "missing DEMO_SPEC.md"
[ "${#FAILS[@]}" -gt 0 ] && finish_run

HEALTH="$(sed -nE 's/^health:[[:space:]]*([^[:space:]]+).*/\1/p' DEMO_SPEC.md | head -n 1)"
HEALTH="${HEALTH:-/}"
if [ -z "${PORT:-}" ]; then
  [ -n "$PY" ] || { fail "PORT not set and python not available to pick a free port"; finish_run; }
  PORT="$("$PY" -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1]);s.close()')"
fi
export PORT
mkdir -p .claude
LOG=".claude/smoke.log"

alive() { kill -0 "$PID" 2>/dev/null; }
cleanup() {
  trap - EXIT INT TERM
  if [ -n "$PID" ]; then
    case "$MODE" in
      winpid) taskkill //PID "$WINPID" //T //F >/dev/null 2>&1 ;;
      *) kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null
         local i=0
         while alive && [ $i -lt 6 ]; do sleep 0.5; i=$((i+1)); done
         if alive; then kill -KILL -- "-$PID" 2>/dev/null || kill -KILL "$PID" 2>/dev/null; fi ;;
    esac
    wait "$PID" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

if command -v setsid >/dev/null 2>&1; then
  MODE=group; setsid ./demo.sh >"$LOG" 2>&1 &
  PID=$!
elif [ -n "$PY" ]; then
  MODE=group; "$PY" -c 'import os,sys;os.setsid();os.execvp(sys.argv[1],sys.argv[1:])' ./demo.sh >"$LOG" 2>&1 &
  PID=$!
else
  ./demo.sh >"$LOG" 2>&1 &
  PID=$!
  WINPID="$(ps -p "$PID" -W 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "$WINPID" ] && command -v taskkill >/dev/null 2>&1; then MODE=winpid
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
deadline=$(( $(date +%s) + TIMEOUT ))
healthy=0
while :; do
  if ! alive; then
    fail "demo.sh exited during boot"; taillog; healthy=-1; break
  fi
  if probe; then healthy=1; break; fi
  [ "$(date +%s)" -ge "$deadline" ] && break
  sleep 0.5
done
if [ "$healthy" = 0 ]; then
  fail "health check $URL not ready after ${TIMEOUT}s"; taillog
fi
# ---- 5. spec ----------------------------------------------------------------
if [ "$healthy" = 1 ]; then
  if [ -f tests/smoke.spec.ts ]; then
    if npx --no-install playwright --version >/dev/null 2>&1; then
      DEMO_URL="http://localhost:$PORT" npx --no-install playwright test tests/smoke.spec.ts || fail "smoke spec failed: tests/smoke.spec.ts"
    else
      echo "SKIP: playwright not installed"; SKIPPED=1
    fi
  elif [ -f tests/smoke.py ]; then
    [ -n "$PY" ] || { fail "python not available for tests/smoke.py"; }
    [ -n "$PY" ] && { DEMO_URL="http://localhost:$PORT" "$PY" tests/smoke.py || fail "smoke spec failed: tests/smoke.py"; }
  else
    echo "SKIP: no smoke spec"; SKIPPED=1
  fi
fi

cleanup
finish_run
