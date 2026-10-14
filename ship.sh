#!/usr/bin/env bash
# ship.sh - idea in, demo branch out. Usage: ./ship.sh "<idea text>" | ./ship.sh path/to/IDEA.md
# Env: QS_BUDGET_USD (default 10), QS_CLAUDE_BIN (default claude).
set -u
die() { echo "ship: $1" >&2; exit 2; }
[ -n "${1:-}" ] && [ "$1" != -h ] || die 'usage: ./ship.sh "<idea text>" | ./ship.sh path/to/IDEA.md'
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || die "working tree is not clean; commit or stash first"
BIN="${QS_CLAUDE_BIN:-claude}"
command -v "$BIN" >/dev/null 2>&1 || die "claude not found; install Claude Code"
if [ -f "$1" ]; then
  [ "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")" = "$ROOT/IDEA.md" ] || cp "$1" "$ROOT/IDEA.md"
else
  printf '%s\n' "$1" > "$ROOT/IDEA.md"
fi
slug="$(head -c 40 "$ROOT/IDEA.md" | tr "A-Z\n" "a-z " | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
[ -n "$slug" ] || slug=demo
branch="demo/$slug"; n=2
while git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"; do branch="demo/$slug-$n"; n=$((n+1)); done
git -C "$ROOT" switch -q -c "$branch" || die "cannot create branch $branch"
git -C "$ROOT" add IDEA.md && git -C "$ROOT" commit -q -m "idea: $slug" || die "commit failed"
cd "$ROOT" && exec "$BIN" --max-budget-usd "${QS_BUDGET_USD:-10}" "Read IDEA.md, then run /shape and show me DEMO_SPEC.md. Stop there."
