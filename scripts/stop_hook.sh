#!/usr/bin/env bash
# Stop hook: block the stop while scripts/smoke.sh fails (once; stop_hook_active breaks the loop).
# Exit 2 + stderr is Claude Code's "block with this reason" channel, so no JSON needs building.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
INPUT="$(cat 2>/dev/null)"

[ -f "$ROOT/DEMO_SPEC.md" ] && [ -f "$ROOT/demo.sh" ] && [ -f "$ROOT/scripts/smoke.sh" ] || exit 0

OUT="$(cd "$ROOT" && bash scripts/smoke.sh 2>&1)" && exit 0

if printf '%s' "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  printf '%s\n' '{"systemMessage":"quickship: smoke.sh is still failing; stopping anyway. Run bash scripts/smoke.sh to see why."}'
  exit 0
fi

[ -n "$OUT" ] || OUT='smoke.sh failed with no output; run bash scripts/smoke.sh'
{ echo "quickship: scripts/smoke.sh failed; fix the cause (never the check), then stop again:"; printf '%s\n' "$OUT" | tail -n 15; } >&2
exit 2
