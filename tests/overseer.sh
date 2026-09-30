#!/usr/bin/env bash
# scripts/overseer.sh: one overseer tick against a stub `claude`.
source "$(dirname "$0")/lib.sh"

CTL="$(tmpdir)"                 # control dir: stub argv/result, never read by overseer.sh
ARGV_FILE="$CTL/argv.log"
RESULT_FILE="$CTL/result.json"
ONCE_MARKER="$CTL/once_marker"
RUN_STATE_PATH_FOR_STUB="$CTL/run_state_path"   # written by tests that need the stub to flip RUN_STATE

STUB_DIR="$(tmpdir)"
cat > "$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
{
  echo "CALL_START"
  printf '%s\n' "$@"
  echo "CALL_END"
} >> "$CLAUDE_STUB_ARGV_FILE"

if [ -n "${CLAUDE_STUB_WRITE_RUN_STATE:-}" ] && [ ! -f "$CLAUDE_STUB_ONCE_MARKER" ]; then
  touch "$CLAUDE_STUB_ONCE_MARKER"
  target="$(cat "$CLAUDE_STUB_RUN_STATE_PATH_FILE")"
  mkdir -p "$(dirname "$target")"
  printf '%s' "$CLAUDE_STUB_WRITE_RUN_STATE" > "$target"
fi

cat "$CLAUDE_STUB_RESULT_FILE"
STUB
chmod +x "$STUB_DIR/claude"
export PATH="$STUB_DIR:$PATH"
export CLAUDE_STUB_ARGV_FILE="$ARGV_FILE"
export CLAUDE_STUB_RESULT_FILE="$RESULT_FILE"
export CLAUDE_STUB_ONCE_MARKER="$ONCE_MARKER"
export CLAUDE_STUB_RUN_STATE_PATH_FILE="$RUN_STATE_PATH_FOR_STUB"
unset CLAUDE_STUB_WRITE_RUN_STATE

# Fresh fake project root: a copy of this repo's overseer agent + scripts,
# never the repo's own .claude/state.
new_project() {
  local p; p="$(tmpdir)"
  mkdir -p "$p/.claude/agents" "$p/.claude/state" "$p/docs" "$p/docs/ledgers"
  cp "$ROOT/.claude/agents/overseer.md" "$p/.claude/agents/overseer.md"
  cp -r "$ROOT/scripts" "$p/scripts"
  printf '%s' "$p"
}

call_count() { grep -c '^CALL_START$' "$ARGV_FILE" 2>/dev/null || true; }
reset_argv() { : > "$ARGV_FILE"; }

printf '%s' '{"is_error":false,"result":"ok","session_id":"x"}' > "$RESULT_FILE"

# --- case: no brief.json -> exit 0, stub not called ---
PROJECT="$(new_project)"
export CLAUDE_PROJECT_DIR="$PROJECT"
reset_argv
expect_exit "no brief.json -> exit 0" 0 bash "$PROJECT/scripts/overseer.sh"
[ "$(call_count)" = "0" ] && ok "no brief.json -> stub not called" || bad "no brief.json -> stub not called (called $(call_count) times)"

# --- case: brief.json present, RUN_STATE DONE -> exit 0, stub not called ---
PROJECT="$(new_project)"
export CLAUDE_PROJECT_DIR="$PROJECT"
printf '{}' > "$PROJECT/.claude/state/brief.json"
printf '%s' '{"state": "DONE", "reason": "mission complete", "at": "2026-01-01T00:00:00Z"}' > "$PROJECT/docs/RUN_STATE"
reset_argv
expect_exit "RUN_STATE DONE -> exit 0" 0 bash "$PROJECT/scripts/overseer.sh"
[ "$(call_count)" = "0" ] && ok "RUN_STATE DONE -> stub not called" || bad "RUN_STATE DONE -> stub not called (called $(call_count) times)"

# --- case: brief.json present, no RUN_STATE -> exit 0, stub called once with the contracted flags ---
PROJECT="$(new_project)"
export CLAUDE_PROJECT_DIR="$PROJECT"
printf '{}' > "$PROJECT/.claude/state/brief.json"
reset_argv
expect_exit "brief present, no RUN_STATE -> exit 0" 0 bash "$PROJECT/scripts/overseer.sh"
[ "$(call_count)" = "1" ] && ok "brief present, no RUN_STATE -> stub called once" || bad "brief present, no RUN_STATE -> stub called once (called $(call_count) times)"
ARGV="$(cat "$ARGV_FILE")"
expect_contains "argv has -p" "$(printf '\n-p\n')" "$(printf '\n%s\n' "$ARGV")"
expect_contains "argv has --max-turns" "--max-turns" "$ARGV"
expect_contains "argv has 8" "$(printf '\n8\n')" "$(printf '\n%s\n' "$ARGV")"
expect_contains "argv has --permission-prompts" "--permission-prompts" "$ARGV"
expect_contains "argv has none" "$(printf '\nnone\n')" "$(printf '\n%s\n' "$ARGV")"
ALLOWED_TOOLS_LINE="$(grep 'Edit(docs/overseer.md)' "$ARGV_FILE" || true)"
expect_contains "allowedTools contains Edit(docs/overseer.md)" "Edit(docs/overseer.md)" "$ALLOWED_TOOLS_LINE"
case "$ALLOWED_TOOLS_LINE" in
  *git*) bad "allowedTools must not contain 'git'" ;;
  *) ok "allowedTools does not contain 'git'" ;;
esac
PROMPT_LINE="$(grep 'force_replan' "$ARGV_FILE" | head -n 1 || true)"
expect_contains "prompt argument contains force_replan" "force_replan" "$PROMPT_LINE"
[ -f "$PROJECT/.claude/state/overseer_last.json" ] && ok "overseer_last.json written" || bad "overseer_last.json written"
LOG_LINES="$(wc -l < "$PROJECT/.claude/state/overseer.log" 2>/dev/null || echo 0)"
[ "$LOG_LINES" = "1" ] && ok "overseer.log has one line" || bad "overseer.log has one line (got $LOG_LINES)"

# --- case: stub reports is_error:true -> exit 1 ---
PROJECT="$(new_project)"
export CLAUDE_PROJECT_DIR="$PROJECT"
printf '{}' > "$PROJECT/.claude/state/brief.json"
printf '%s' '{"is_error":true}' > "$RESULT_FILE"
reset_argv
expect_exit "is_error:true -> exit 1" 1 bash "$PROJECT/scripts/overseer.sh"
printf '%s' '{"is_error":false,"result":"ok","session_id":"x"}' > "$RESULT_FILE"

# --- case: --loop 1 with a stub that flips RUN_STATE terminal on its first call -> returns after one tick ---
PROJECT="$(new_project)"
export CLAUDE_PROJECT_DIR="$PROJECT"
printf '{}' > "$PROJECT/.claude/state/brief.json"
printf '%s' "$PROJECT/docs/RUN_STATE" > "$RUN_STATE_PATH_FOR_STUB"
rm -f "$ONCE_MARKER"
export CLAUDE_STUB_WRITE_RUN_STATE='{"state": "DONE", "reason": "stub finished", "at": "2026-01-01T00:00:00Z"}'
reset_argv
expect_exit "--loop 1 returns after one tick" 0 timeout 30 bash "$PROJECT/scripts/overseer.sh" --loop 1
[ "$(call_count)" = "1" ] && ok "--loop 1 -> stub called exactly once" || bad "--loop 1 -> stub called exactly once (called $(call_count) times)"
unset CLAUDE_STUB_WRITE_RUN_STATE

finish
