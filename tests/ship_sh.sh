#!/usr/bin/env bash
# ship.sh: idea -> branch -> claude /shape. claude is stubbed; no LLM calls.
source "$(dirname "$0")/lib.sh"
F="$(tmpdir)"
git -C "$F" init -q -b main
git -C "$F" config user.name test; git -C "$F" config user.email test@example.com
echo hi > "$F/README"; cp "$ROOT/ship.sh" "$F/ship.sh"
git -C "$F" add -A && git -C "$F" commit -qm init
S="$(tmpdir)"; mkdir -p "$S/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/claude.args"\nexit 0\n' "$S" > "$S/bin/claude"; chmod +x "$S/bin/claude"
export QS_CLAUDE_BIN="$S/bin/claude"
run() { ( cd "$F" && bash ship.sh "$@" ); }
branch() { git -C "$F" rev-parse --abbrev-ref HEAD; }

expect_exit "no arg exits 2" 2 run
echo dirty > "$F/junk.txt"
expect_exit "dirty tree exits 2" 2 run "a todo app"
[ -z "$(git -C "$F" branch --list 'demo/*')" ] && ok "no branch on dirty tree" || bad "branch created on dirty tree"
rm "$F/junk.txt"

base="$(git -C "$F" rev-list --count HEAD)"
expect_exit "text idea exits 0" 0 run "A Todo App, with Tags!"
[ "$(cat "$F/IDEA.md")" = "A Todo App, with Tags!" ] && ok "IDEA.md has text" || bad "IDEA.md content wrong"
[ "$(branch)" = "demo/a-todo-app-with-tags" ] && ok "slug branch" || bad "branch is $(branch)"
[ "$(( $(git -C "$F" rev-list --count HEAD) - base ))" = 1 ] && ok "one new commit" || bad "commit count wrong"
args="$(cat "$S/claude.args")"
case "$args" in *--max-budget-usd*) bad "args must not contain --max-budget-usd";; *) ok "no --max-budget-usd";; esac
expect_contains "runs /shape" "Read IDEA.md, then run /shape" "$args"

# same idea twice, back to back, from the demo branch (IDEA.md already committed)
rm -f "$S/claude.args"
expect_exit "same idea again exits 0" 0 run "A Todo App, with Tags!"
[ -s "$S/claude.args" ] && ok "same idea again reaches claude" || bad "same idea again did not reach claude"
[ "$(branch)" = "demo/a-todo-app-with-tags-2" ] && ok "same idea again gets -2" || bad "same idea branch is $(branch)"

# ./ship.sh IDEA.md with IDEA.md already committed
rm -f "$S/claude.args"
expect_exit "committed IDEA.md exits 0" 0 run IDEA.md
[ -s "$S/claude.args" ] && ok "committed IDEA.md reaches claude" || bad "committed IDEA.md did not reach claude"
expect_exit "--help exits 2" 2 run --help

git -C "$F" switch -q main
printf 'idea from a file\nmore\n' > "$F/my idea.md"; git -C "$F" add -A; git -C "$F" commit -qm f
expect_exit "file idea exits 0" 0 run "my idea.md"
cmp -s "$F/my idea.md" "$F/IDEA.md" && ok "IDEA.md equals file" || bad "IDEA.md differs from file"

git -C "$F" switch -q main
run "A Todo App, with Tags!" >/dev/null 2>&1
[ "$(branch)" = "demo/a-todo-app-with-tags-4" ] && ok "duplicate slug gets next free suffix" || bad "dup branch is $(branch)"

git -C "$F" switch -q main
QS_CLAUDE_BIN=/nonexistent expect_exit "missing claude exits 2" 2 run "x idea"
finish
