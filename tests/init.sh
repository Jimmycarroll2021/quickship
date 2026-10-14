#!/usr/bin/env bash
# scripts/init.sh: one-way copy of the harness into a target project. No LLM calls.
source "$(dirname "$0")/lib.sh"
INIT="$ROOT/scripts/init.sh"
FILES="CLAUDE.md .claude/settings.json .claude/agents/shaper.md .claude/agents/builder.md .claude/agents/verifier.md .claude/agents/polisher.md .claude/commands/shape.md .claude/commands/build.md .claude/commands/verify.md .claude/commands/polish.md scripts/smoke.sh scripts/stop_hook.sh ship.sh .gitattributes"
snap() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort ); }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
t="$(tmpdir)/proj"
expect_exit "fresh target exits 0" 0 bash "$INIT" "$t"
expect_contains "prints next step" "next: cd \"$t\" && ./ship.sh \"your idea\"" "$OUT"
[ -z "$(git -C "$t" status --porcelain)" ] && ok "tree clean after init" || bad "tree not clean after init: $(git -C "$t" status --porcelain | head -n 3)"
[ "$(git -C "$t" log -1 --format=%s)" = "quickship: install" ] && ok "install commit message" || bad "last commit is: $(git -C "$t" log -1 --format=%s 2>&1)"
for f in $FILES; do [ -f "$t/$f" ] && ok "installed $f" || bad "missing $f"; done
[ -d "$t/.git" ] && ok "git initialised" || bad "no .git in target"
for f in scripts/smoke.sh scripts/stop_hook.sh ship.sh; do [ -x "$t/$f" ] && ok "$f executable" || bad "$f not executable"; done
grep -qxF ".claude/smoke.log" "$t/.gitignore" && ok ".gitignore has smoke.log" || bad ".gitignore lacks .claude/smoke.log"
grep -qxF ".claude/state/" "$t/.gitignore" && ok ".gitignore has state/" || bad ".gitignore lacks .claude/state/"
grep -qxF "node_modules/" "$t/.gitignore" && ok ".gitignore has node_modules/" || bad ".gitignore lacks node_modules/"
grep -qxF "__pycache__/" "$t/.gitignore" && ok ".gitignore has __pycache__/" || bad ".gitignore lacks __pycache__/"
for f in scripts/gate.sh scripts/policy.py scripts/runner.py .claude/agents/worker.md BRIEF.example.yaml .quickship; do
  [ -e "$t/$f" ] && bad "target must not contain $f" || ok "no $f in target"
done

# second run: skips everything, changes nothing
before="$(snap "$t")"
expect_exit "second run exits 0" 0 bash "$INIT" "$t"
for f in $FILES; do expect_contains "second run skips $f" "skip $f" "$OUT"; done
[ "$(snap "$t")" = "$before" ] && ok "second run changes no files" || bad "second run changed the file set"
[ "$(grep -cxF .claude/smoke.log "$t/.gitignore")" = 1 ] && ok ".gitignore not duplicated" || bad ".gitignore duplicated"

# a modified CLAUDE.md is kept byte-identical
t2="$(tmpdir)/proj2"; mkdir -p "$t2"; printf 'my own rules\n' > "$t2/CLAUDE.md"
expect_exit "existing CLAUDE.md run exits 0" 0 bash "$INIT" "$t2"
[ "$(cat "$t2/CLAUDE.md")" = "my own rules" ] && ok "CLAUDE.md kept" || bad "CLAUDE.md was overwritten"
expect_contains "reports skip CLAUDE.md" "skip CLAUDE.md" "$OUT"

# unrelated uncommitted changes are not swept into the install commit
t3="$(tmpdir)/proj3"; mkdir -p "$t3"; git -C "$t3" init -q
echo base > "$t3/app.txt"; git -C "$t3" add app.txt; git -C "$t3" commit -qm base
echo changed > "$t3/app.txt"; echo new > "$t3/untracked.txt"
expect_exit "init into dirty repo exits 0" 0 bash "$INIT" "$t3"
por="$(git -C "$t3" status --porcelain)"
expect_contains "unrelated modification stays uncommitted" " M app.txt" "$por"
expect_contains "unrelated untracked file stays untracked" "?? untracked.txt" "$por"
[ "$(git -C "$t3" log -1 --format=%s)" = "quickship: install" ] && ok "dirty repo: install commit made" || bad "dirty repo: last commit is $(git -C "$t3" log -1 --format=%s)"
[ "$(git -C "$t3" show --stat --format= HEAD | grep -c 'app.txt\|untracked.txt')" = 0 ] && ok "install commit excludes unrelated files" || bad "install commit contains unrelated files"

# end to end: init, then ./ship.sh "idea" must reach claude (stubbed), not die on a dirty tree
E="$(tmpdir)"; mkdir -p "$E/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/claude.args"\nexit 0\n' "$E" > "$E/bin/claude"; chmod +x "$E/bin/claude"
t4="$(tmpdir)/proj4"; bash "$INIT" "$t4" >/dev/null 2>&1
e2e() { ( cd "$t4" && QS_CLAUDE_BIN="$E/bin/claude" ./ship.sh "an idea" ); }
expect_exit "init then ship.sh exits 0" 0 e2e
[ -s "$E/claude.args" ] && ok "ship.sh reached claude stub" || bad "ship.sh did not reach claude: $OUT"

# target .gitignore ignoring .claude/: install still commits cleanly
t5="$(tmpdir)/proj5"; mkdir -p "$t5"; git -C "$t5" init -q
printf '.claude/\n' > "$t5/.gitignore"; git -C "$t5" add .gitignore; git -C "$t5" commit -qm base
expect_exit "init with .claude/ ignored exits 0" 0 bash "$INIT" "$t5"
[ -z "$(git -C "$t5" status --porcelain)" ] && ok "ignored .claude/: tree clean" || bad "ignored .claude/: dirty: $(git -C "$t5" status --porcelain | head -n 3)"
[ -n "$(git -C "$t5" ls-files .claude/settings.json)" ] && ok "ignored .claude/: settings.json tracked" || bad "settings.json not tracked"

# a committed non-executable ship.sh is not chmod'ed
t6="$(tmpdir)/proj6"; mkdir -p "$t6"; git -C "$t6" init -q
printf '#!/bin/sh\n' > "$t6/ship.sh"; chmod 644 "$t6/ship.sh"; git -C "$t6" add ship.sh; git -C "$t6" commit -qm base
expect_exit "init with existing ship.sh exits 0" 0 bash "$INIT" "$t6"
[ -z "$(git -C "$t6" status --porcelain)" ] && ok "existing ship.sh: no mode change" || bad "existing ship.sh dirtied: $(git -C "$t6" status --porcelain | head -n 3)"

# usage and self-target
expect_exit "target = repo root exits 2" 2 bash "$INIT" "$ROOT"
expect_exit "no args exits 2" 2 bash "$INIT"
expect_exit "-h exits 2" 2 bash "$INIT" -h

# the installed smoke.sh runs
F="$(tmpdir)/smoke"; bash "$INIT" "$F" >/dev/null 2>&1
git -C "$F" config user.name test; git -C "$F" config user.email test@example.com
cp "$(mkfixture)/server.py" "$F/server.py"
printf '#!/usr/bin/env bash\nexec "%s" server.py\n' "$QS_PYTHON" >"$F/demo.sh"; chmod +x "$F/demo.sh"
printf 'run: ./demo.sh\nhealth: /healthz\n' >"$F/DEMO_SPEC.md"
git -C "$F" add -A && git -C "$F" commit -qm fixture
OUT="$(cd "$F" && SMOKE_BOOT_TIMEOUT=10 bash scripts/smoke.sh 2>&1)"
[ "$(printf '%s\n' "$OUT" | tail -n1)" = "PASS (spec skipped)" ] && ok "installed smoke.sh passes" || bad "installed smoke.sh: $(printf '%s' "$OUT" | tail -n 3)"
finish
