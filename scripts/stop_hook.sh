#!/usr/bin/env bash
# Stop hook: block the stop while scripts/smoke.sh fails (once; stop_hook_active breaks the loop).
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
INPUT="$(cat 2>/dev/null)"

if printf '%s' "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  printf '%s\n' '{"systemMessage":"quickship: smoke.sh is still failing; stopping anyway. Run bash scripts/smoke.sh to see why."}'
  exit 0
fi

[ -f "$ROOT/DEMO_SPEC.md" ] && [ -f "$ROOT/demo.sh" ] || exit 0
[ -f "$ROOT/scripts/smoke.sh" ] || exit 0

LOG="$(mktemp "${TMPDIR:-/tmp}/qs-smoke.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
if ( cd "$ROOT" && bash scripts/smoke.sh ) >"$LOG" 2>&1; then
  exit 0
fi

REASON="$(tail -n 15 "$LOG" | tr -d '\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')"
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
