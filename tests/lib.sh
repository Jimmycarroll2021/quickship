#!/usr/bin/env bash
# Shared helpers for tests/*.sh. Source this file; call finish at the end.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export QS_PYTHON="${QS_PYTHON:-$(command -v python3 || command -v python)}"
unset CLAUDE_PROJECT_DIR
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1" >&2; }
# expect_exit <label> <want-exit> <cmd...>   (stdout/stderr of cmd go to $OUT)
expect_exit() {
  local label=$1 want=$2; shift 2
  OUT="$("$@" 2>&1)"; local got=$?
  if [ "$got" = "$want" ]; then ok "$label"; else bad "$label (want exit $want, got $got): $(printf '%s' "$OUT" | tail -n 3)"; fi
}
expect_contains() { # expect_contains <label> <needle> <haystack>
  case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing '$2' in: $(printf '%s' "$3" | tail -n 3))";; esac
}
# mkfixture -> echoes a fresh git repo with a python http.server demo.sh, DEMO_SPEC.md and scripts/smoke.sh
mkfixture() {
  local d; d="$(tmpdir)"
  git -C "$d" init -q
  git -C "$d" config user.name test
  git -C "$d" config user.email test@example.com
  cat >"$d/server.py" <<'PYEOF'
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/healthz"):
            self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
        else:
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
HTTPServer(("", int(os.environ["PORT"])), H).serve_forever()
PYEOF
  printf '#!/usr/bin/env bash\nexec python3 server.py\n' >"$d/demo.sh"; chmod +x "$d/demo.sh"
  printf 'run: ./demo.sh\nhealth: /healthz\n' >"$d/DEMO_SPEC.md"
  mkdir -p "$d/scripts"; cp "$ROOT/scripts/smoke.sh" "$d/scripts/smoke.sh" 2>/dev/null
  git -C "$d" add -A && git -C "$d" commit -qm fixture
  echo "$d"
}
tmpdir() { mktemp -d "${TMPDIR:-/tmp}/qs-test.XXXXXX"; }
finish() { echo "$(basename "$0"): $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]; }
