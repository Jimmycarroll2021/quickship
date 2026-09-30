#!/usr/bin/env bash
# scripts/run.sh: the launcher. Validates the brief, resumes or starts the lead headlessly with the allow list
# passed via --allowedTools, backs off on restarts, gives up after 5, and never calls claude on a terminal run.
source "$(dirname "$0")/lib.sh"
mk() { # fresh repo with scripts/, agents, settings, example brief, and a stub `claude` first on PATH
  local d; d="$(tmpdir)"; git init -q -b main "$d"
  cp -r "$ROOT/scripts" "$ROOT/.claude" "$ROOT/BRIEF.example.yaml" "$d/" 2>/dev/null; rm -rf "$d/.claude/worktrees" "$d/.claude/state"
  cp "$d/BRIEF.example.yaml" "$d/BRIEF.yaml"; mkdir -p "$d/docs/ledgers"
  (cd "$d" && git -c core.autocrlf=false add -A && git -c core.autocrlf=false -c user.email=t@t -c user.name=t commit -qm init)
  mkdir -p "$d/bin"; cat > "$d/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG"
[ -n "${STUB_RUN_STATE:-}" ] && printf '%s' "$STUB_RUN_STATE" > docs/RUN_STATE
printf '{"is_error":false,"session_id":"sess-123","total_cost_usd":0.5,"result":"ok"}'
EOF
  chmod +x "$d/bin/claude"; echo "$d"
}
run() { (cd "$1" && PATH="$1/bin:$PATH" STUB_LOG="$1/stub.log" QS_SLEEP=0 QS_OVERSEER=0 bash scripts/run.sh "${@:2}"); }

d="$(mk)"
expect_exit "fresh start exits 0" 0 run "$d"
expect_contains "fresh start calls claude -p" "-p" "$(cat "$d/stub.log")"
expect_contains "passes --permission-prompts none" "--permission-prompts" "$(cat "$d/stub.log")"
expect_contains "passes the allow list via --allowedTools" "--allowedTools" "$(cat "$d/stub.log")"
expect_contains "allow list contains a settings.json rule" "Bash(git worktree *)" "$(cat "$d/stub.log")"
expect_contains "never uses --bare" "" "$(grep -c -- '--bare' "$d/stub.log" | sed 's/^0$//')"
expect_contains "drops the user's MCP servers (cost, tool bloat)" "--strict-mcp-config" "$(cat "$d/stub.log")"
expect_contains "records the session id" "sess-123" "$(cat "$d/.claude/state/session_id")"
expect_contains "restart counter is 1" "1" "$(cat "$d/.claude/state/restarts")"
expect_contains "brief was validated" "\"goal\"" "$(cat "$d/.claude/state/brief.json")"
expect_contains "last run json saved" "sess-123" "$(cat "$d/.claude/state/last_run.json")"

: > "$d/stub.log"
expect_exit "second start exits 0" 0 run "$d"
expect_contains "second start resumes the session" "--resume" "$(cat "$d/stub.log")"
expect_contains "resume uses the saved id" "sess-123" "$(cat "$d/stub.log")"
expect_contains "restart counter is 2" "2" "$(cat "$d/.claude/state/restarts")"

printf '{"state":"DONE","reason":"x","at":"2026-01-01T00:00:00Z"}' > "$d/docs/RUN_STATE"; : > "$d/stub.log"
expect_exit "terminal RUN_STATE: exit 0 without claude" 0 run "$d"
expect_contains "terminal RUN_STATE: claude not called" "" "$(cat "$d/stub.log")"
rm "$d/docs/RUN_STATE"

echo 5 > "$d/.claude/state/restarts"; : > "$d/stub.log"
expect_exit "restart limit: exit 3" 3 run "$d"
expect_contains "restart limit: writes SAFE_STOP" "SAFE_STOP" "$(cat "$d/docs/RUN_STATE")"
expect_contains "restart limit: claude not called" "" "$(cat "$d/stub.log")"

d2="$(mk)"; rm "$d2/BRIEF.yaml"
expect_exit "missing brief: exit 2" 2 run "$d2"

d3="$(mk)"
expect_exit "stub writing terminal state: run returns 0" 0 bash -c "cd '$d3' && PATH='$d3/bin:$PATH' STUB_LOG='$d3/stub.log' STUB_RUN_STATE='{\"state\":\"DONE\",\"reason\":\"ok\",\"at\":\"x\"}' QS_SLEEP=0 QS_OVERSEER=0 bash scripts/run.sh"
expect_contains "run reports the terminal state" "DONE" "$OUT"

# --- killed mid-run: no JSON result, but the budget hook has recorded the transcript path, whose basename is the
# session id; run.sh must save that id so the next start resumes the same session instead of a fresh one ---
d4="$(mk)"; cat > "$d4/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG"
mkdir -p .claude/state; printf '%s' 'C:\Users\x\.claude\projects\p\abcd-1234.jsonl' > .claude/state/transcript_path
exit 137
EOF
run "$d4" >/dev/null 2>&1
expect_contains "killed run: session id derived from transcript path" "abcd-1234" "$(cat "$d4/.claude/state/session_id" 2>/dev/null)"
cp "$d3/bin/claude" "$d4/bin/claude"   # the lead comes back healthy
: > "$d4/stub.log"; run "$d4" >/dev/null 2>&1
expect_contains "killed run: next start resumes that session" "--resume" "$(cat "$d4/stub.log")"
expect_contains "killed run: resume uses the derived id" "abcd-1234" "$(cat "$d4/stub.log")"

# --- stale terminal state from an earlier, merged mission (different goal): archived, then the run starts ---
d5="$(mk)"
printf '{"state":"DONE","reason":"old","at":"2026-09-01T00:00:00Z"}' > "$d5/docs/RUN_STATE"
printf '{"goal":"An earlier mission","plan":[],"facts":[],"assumptions":[],"blocked":[],"replan_count":0,"stall_count":0,"is_complete":true}' > "$d5/docs/ledgers/task.json"
printf 'old-session' > "$d5/.claude/state/session_id" 2>/dev/null || { mkdir -p "$d5/.claude/state"; printf 'old-session' > "$d5/.claude/state/session_id"; }
expect_exit "stale terminal state: run exits 0" 0 run "$d5"
expect_contains "stale terminal state: claude is called fresh" "-p" "$(cat "$d5/stub.log")"
expect_contains "stale terminal state: not resumed with the old id" "" "$(grep -c 'old-session' "$d5/stub.log" | sed 's/^0$//')"
expect_contains "stale terminal state: old run archived under docs/runs" "1" "$(ls -d "$d5"/docs/runs/*/ 2>/dev/null | wc -l | tr -d ' ')"
finish
