#!/usr/bin/env bash
# scripts/program.sh: runs docs/missions/NN-*.yaml in order. Each mission starts from the previous mission's branch
# with mission.base set to it, stops at the first mission that is not DONE, and resumes by skipping DONE missions.
source "$(dirname "$0")/lib.sh"
mk() { # repo with scripts/, two mission briefs and a stub lead (QS_RUN) that branches, commits and ends terminal
  local d; d="$(tmpdir)"; git init -q -b main "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t; git -C "$d" config core.autocrlf false
  cp -r "$ROOT/scripts" "$d/"; mkdir -p "$d/docs/missions"
  awk '/^  goal:/{print "  goal: \"alpha\""; next} {print}' "$ROOT/BRIEF.example.yaml" > "$d/docs/missions/01-alpha.yaml"
  awk '/^  goal:/{print "  goal: \"beta\""; next} {print}' "$ROOT/BRIEF.example.yaml" > "$d/docs/missions/02-beta.yaml"
  (cd "$d" && git add -A && git commit -qm init)
  cat > "$d/stub_run.sh" <<'STUB'
#!/usr/bin/env bash
rm -f docs/RUN_STATE                                   # run.sh archives the previous mission's state
g="$(sed -n 's/^  goal: "\(.*\)"/\1/p' BRIEF.yaml)"
printf '%s|%s|%s\n' "$g" "$(git rev-parse HEAD)" "$(sed -n 's/^  base: "\(.*\)"/\1/p' BRIEF.yaml)" >> "$STUB_LOG"
git checkout -q -b "mission/$g" 2>/dev/null || git checkout -q "mission/$g"
echo "$g" > "$g.txt"; git add "$g.txt"; git commit -qm "$g"
state=DONE; [ "$g" = "${STUB_PARTIAL:-}" ] && state=DONE_PARTIAL
printf '{"state":"%s","reason":"r","at":"x"}\n' "$state" > docs/RUN_STATE
printf 'PR: https://github.com/example-owner/x/pull/%s\n' "${#g}" > docs/REPORT.md
STUB
  chmod +x "$d/stub_run.sh"; echo "$d"
}
prog() { (cd "$1" && QS_RUN="$1/stub_run.sh" STUB_LOG="$1/stub.log" bash scripts/program.sh "${@:2}"); }

d="$(mk)"
expect_exit "two missions: exit 0" 0 prog "$d"
expect_contains "both missions ran" "2" "$(wc -l < "$d/stub.log" | tr -d ' ')"
first="$(sed -n 1p "$d/stub.log")"; second="$(sed -n 2p "$d/stub.log")"
expect_contains "mission 1 has no base" "alpha||" "${first%%|*}||${first##*|}"
expect_contains "mission 2 base is mission 1's branch" "mission/alpha" "${second##*|}"
tip="$(git -C "$d" rev-parse mission/alpha)"; started="$(printf '%s' "$second" | cut -d'|' -f2)"
[ "$(git -C "$d" rev-parse "$started^")" = "$tip" ] && ok "mission 2 starts from mission 1's tip (plus the brief commit)" || bad "mission 2 starts from mission 1's tip"
expect_contains "main untouched" "$(git -C "$d" rev-parse main)" "$(git -C "$d" log -1 --format=%H main)"
[ "$(git -C "$d" rev-list --count main)" = 1 ] && ok "no commits on main" || bad "no commits on main"
expect_contains "PROGRAM.md lists mission 2" "02-beta.yaml" "$(cat "$d/docs/PROGRAM.md")"
expect_contains "PROGRAM.md has the PR link" "pull/" "$(cat "$d/docs/PROGRAM.md")"
expect_contains "final message says merge the stack" "merge" "$OUT"

: > "$d/stub.log"
expect_exit "re-run: exit 0" 0 prog "$d"
expect_contains "re-run: nothing ran" "0" "$(wc -l < "$d/stub.log" | tr -d ' ')"

d2="$(mk)"
expect_exit "mission 1 partial: exit 3" 3 bash -c "cd '$d2' && QS_RUN='$d2/stub_run.sh' STUB_LOG='$d2/stub.log' STUB_PARTIAL=alpha bash scripts/program.sh"
expect_contains "mission 1 partial: mission 2 not run" "1" "$(wc -l < "$d2/stub.log" | tr -d ' ')"
expect_contains "mission 1 partial: names the state" "DONE_PARTIAL" "$OUT"

d6="$(mk)"
expect_exit "mission 2 partial: exit 3" 3 bash -c "cd '$d6' && QS_RUN='$d6/stub_run.sh' STUB_LOG='$d6/stub.log' STUB_PARTIAL=beta bash scripts/program.sh"
printf '{"schema":3}\n' > "$d6/.claude/state/controller.json"
echo recovery > "$d6/beta.txt"
resume_tip="$(git -C "$d6" rev-parse HEAD)"
: > "$d6/stub.log"
expect_exit "resume preserves dirty mission checkout" 0 prog "$d6"
expect_contains "resume does not detach back to predecessor" "$resume_tip" "$(head -1 "$d6/stub.log")"
expect_contains "resume names the preserved checkout" "existing checkout" "$OUT"

d3="$(mk)"; rm "$d3"/docs/missions/*.yaml
expect_exit "no missions: exit 2" 2 prog "$d3"
d4="$(mk)"; sed -i '/^  steps:/d' "$d4/docs/missions/02-beta.yaml"
expect_exit "invalid mission brief: exit 2 before anything runs" 2 prog "$d4"
expect_contains "invalid brief: nothing ran" "" "$(cat "$d4/stub.log" 2>/dev/null)"

# run.sh rejecting the brief (exit 2, before it archives the last mission's DONE) must not read as DONE
d5="$(mk)"; printf '#!/usr/bin/env bash
exit 2
' > "$d5/stub_run.sh"
printf '{"state":"DONE","reason":"old","at":"x"}
' > "$d5/docs/RUN_STATE"
expect_exit "run.sh exit 2 with a stale DONE: exit 3" 3 prog "$d5"
finish
