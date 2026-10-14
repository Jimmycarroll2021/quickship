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
# A staged or modified .gitignore would be swept into the install commit; untracked ("??") or clean is fine.
case "$(git -C "$T" status --porcelain -- .gitignore)" in
  ""|"??"*) ;;
  *) echo "init: .gitignore has uncommitted changes; commit them first" >&2; exit 2;;
esac
added=()
# abort <msg>: undo the files copied so far, so a re-run starts clean instead of skipping them as "existing"
abort() { echo "init: $1" >&2; [ "${#added[@]}" -gt 0 ] && (cd "$T" && rm -f -- "${added[@]}"); exit 2; }
for f in $FILES; do
  if [ -e "$T/$f" ]; then echo "skip $f"; else
    mkdir -p "$(dirname "$T/$f")" || abort "cannot create directory for $T/$f"
    cp "$SRC/$f" "$T/$f" || abort "cannot copy $f to $T/$f"
    echo "add $f"; added+=("$f")
    case "$f" in *.sh) chmod +x "$T/$f";; esac
  fi
done
for line in .claude/smoke.log .claude/state/ node_modules/ __pycache__/; do
  grep -qxF -- "$line" "$T/.gitignore" 2>/dev/null && continue
  [ -s "$T/.gitignore" ] && [ -n "$(tail -c1 "$T/.gitignore")" ] && echo >> "$T/.gitignore"
  echo "$line" >> "$T/.gitignore"
done

# Commit only what init added (plus .gitignore) so ship.sh finds a clean tree.
paths=("${added[@]+"${added[@]}"}" .gitignore)
git -C "$T" add -f -- "${paths[@]}" >/dev/null
if ! git -C "$T" diff --cached --quiet -- "${paths[@]}"; then
  git -C "$T" commit -q -m "quickship: install" -- "${paths[@]}" >/dev/null \
    || { echo "init: install commit failed (git's error is above; a missing user.name/user.email is the usual cause)." >&2
         echo "      fix it, then run: git -C \"$T\" commit -m \"quickship: install\" -- ${paths[*]}" >&2; exit 2; }
fi
echo "next: cd \"$T\" && ./ship.sh \"your idea\""
