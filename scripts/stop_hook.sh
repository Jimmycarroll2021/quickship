#!/usr/bin/env bash
# Stop hook: block the stop while scripts/smoke.sh fails (once; stop_hook_active breaks the loop).
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
INPUT="$(cat 2>/dev/null)"

[ -f "$ROOT/DEMO_SPEC.md" ] && [ -f "$ROOT/demo.sh" ] && [ -f "$ROOT/scripts/smoke.sh" ] || exit 0

LOG="$(mktemp "${TMPDIR:-/tmp}/qs-smoke.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
( cd "$ROOT" && bash scripts/smoke.sh ) >"$LOG" 2>&1 && exit 0

if printf '%s' "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  printf '%s\n' '{"systemMessage":"quickship: smoke.sh is still failing; stopping anyway. Run bash scripts/smoke.sh to see why."}'
  exit 0
fi

# Strip control chars (keep tab/newline), then escape for JSON in one sed; join lines with \n.
REASON="$(tail -n 15 "$LOG" | tr -d '\r' | tr -d '\000-\010\013-\037\177' | sed -e ':a' -e '$!{N;ba' -e '}' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" -e 's/\n/\\n/g')"
[ -n "$REASON" ] || REASON='smoke.sh failed with no output; run bash scripts/smoke.sh'
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
