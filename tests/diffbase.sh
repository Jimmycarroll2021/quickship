#!/usr/bin/env bash
# diffbase.sh prints the ref to diff against: origin/main, else main, else the root commit.
source "$(dirname "$0")/lib.sh"
commit() { git -c user.email=t@t -c user.name=t commit -qm "$1" --allow-empty; }
r1="$(tmpdir)"; ( cd "$r1" && git init -q -b main . && commit a && git checkout -q -b feat && commit b )
expect_contains "no remote -> main" "main" "$(cd "$r1" && bash "$ROOT/scripts/diffbase.sh")"
r2="$(tmpdir)"; ( cd "$r2" && git init -q -b feat . && commit a )
root="$(cd "$r2" && git rev-list --max-parents=0 HEAD)"
expect_contains "no main -> root commit" "$root" "$(cd "$r2" && bash "$ROOT/scripts/diffbase.sh")"
bare="$(tmpdir)"; git init -q --bare "$bare"
( cd "$r1" && git remote add origin "$bare" && git push -q origin main )
expect_contains "remote main -> origin/main" "origin/main" "$(cd "$r1" && bash "$ROOT/scripts/diffbase.sh")"
finish
