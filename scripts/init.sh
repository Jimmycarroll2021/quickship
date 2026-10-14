#!/usr/bin/env bash
# Install quickship into a target project: a one-way copy that never overwrites.
#   bash scripts/init.sh <target-dir>
set -u
[ $# = 1 ] && [ "$1" != -h ] && [ "$1" != --help ] || { echo "usage: bash scripts/init.sh <target-dir>" >&2; exit 2; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" || SRC="$(cd "$here/.." && pwd)"
FILES="CLAUDE.md .claude/settings.json .claude/agents/shaper.md .claude/agents/builder.md .claude/agents/verifier.md .claude/agents/polisher.md .claude/commands/shape.md .claude/commands/build.md .claude/commands/verify.md .claude/commands/polish.md scripts/smoke.sh scripts/stop_hook.sh ship.sh .gitattributes"
mkdir -p "$1" || exit 2
T="$(cd "$1" && pwd -P)"
[ "$T" != "$(cd "$SRC" && pwd -P)" ] || { echo "init: target is the quickship repo itself" >&2; exit 2; }
[ -e "$T/.git" ] || git init -q "$T"
for f in $FILES; do
  if [ -e "$T/$f" ]; then echo "skip $f"; else mkdir -p "$(dirname "$T/$f")" && cp "$SRC/$f" "$T/$f" && echo "add $f"; fi
  case "$f" in *.sh) chmod +x "$T/$f";; esac
done
for line in .claude/smoke.log .claude/state/; do
  grep -qxF -- "$line" "$T/.gitignore" 2>/dev/null && continue
  [ -s "$T/.gitignore" ] && [ -n "$(tail -c1 "$T/.gitignore")" ] && echo >> "$T/.gitignore"
  echo "$line" >> "$T/.gitignore"
done
echo "next: cd $T && ./ship.sh \"your idea\""
