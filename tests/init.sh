#!/usr/bin/env bash
# scripts/init.sh: one-way copy of the harness into a target project. No LLM calls.
source "$(dirname "$0")/lib.sh"
INIT="$ROOT/scripts/init.sh"
FILES="CLAUDE.md .claude/settings.json .claude/agents/shaper.md .claude/agents/builder.md .claude/agents/verifier.md .claude/agents/polisher.md .claude/commands/shape.md .claude/commands/build.md .claude/commands/verify.md .claude/commands/polish.md scripts/smoke.sh scripts/stop_hook.sh ship.sh .gitattributes"
snap() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort ); }

t="$(tmpdir)/proj"
expect_exit "fresh target exits 0" 0 bash "$INIT" "$t"
expect_contains "prints next step" "next: cd $t && ./ship.sh \"your idea\"" "$OUT"
for f in $FILES; do [ -f "$t/$f" ] && ok "installed $f" || bad "missing $f"; done
[ -d "$t/.git" ] && ok "git initialised" || bad "no .git in target"
for f in scripts/smoke.sh scripts/stop_hook.sh ship.sh; do [ -x "$t/$f" ] && ok "$f executable" || bad "$f not executable"; done
grep -qxF ".claude/smoke.log" "$t/.gitignore" && ok ".gitignore has smoke.log" || bad ".gitignore lacks .claude/smoke.log"
grep -qxF ".claude/state/" "$t/.gitignore" && ok ".gitignore has state/" || bad ".gitignore lacks .claude/state/"
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

# usage and self-target
expect_exit "target = repo root exits 2" 2 bash "$INIT" "$ROOT"
expect_exit "no args exits 2" 2 bash "$INIT"
expect_exit "-h exits 2" 2 bash "$INIT" -h

# the installed smoke.sh runs
F="$(tmpdir)/smoke"; bash "$INIT" "$F" >/dev/null 2>&1
git -C "$F" config user.name test; git -C "$F" config user.email test@example.com
cp "$(mkfixture)/server.py" "$F/server.py"
printf '#!/usr/bin/env bash\nexec python3 server.py\n' >"$F/demo.sh"; chmod +x "$F/demo.sh"
printf 'run: ./demo.sh\nhealth: /healthz\n' >"$F/DEMO_SPEC.md"
git -C "$F" add -A && git -C "$F" commit -qm fixture
OUT="$(cd "$F" && SMOKE_BOOT_TIMEOUT=10 bash scripts/smoke.sh 2>&1)"
[ "$(printf '%s\n' "$OUT" | tail -n1)" = "PASS (spec skipped)" ] && ok "installed smoke.sh passes" || bad "installed smoke.sh: $(printf '%s' "$OUT" | tail -n 3)"
finish
