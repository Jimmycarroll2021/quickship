#!/usr/bin/env bash
# Budgets: scripts/budget.py (usage/cost/time/steps vs brief.json) and scripts/hooks/budget.sh (Pre/PostToolUse).
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"
S="$CLAUDE_PROJECT_DIR/.claude/state"
budget() { "$QS_PYTHON" "$ROOT/scripts/budget.py" "$@"; }
pre_bash() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"transcript_path":"%s"}' "$1" "${2:-}"; }
pre_file() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"},"transcript_path":"%s"}' "$1" "$2" "${3:-}"; }

# --- no active run
expect_exit "budget.py without brief.json exits 2" 2 budget
expect_exit "budget.sh without brief.json is a no-op" 0 hook budget.sh "$(pre_bash "npm test")"

# --- fixture run
mkdir -p "$S"
write_brief() { # write_brief <tokens> <cost> <wall_min> <steps>
  printf '{"mission":{"goal":"g","deliverables":["README.md"]},"success_criteria":[],"budgets":{"tokens":%s,"cost_usd":%s,"wall_clock_min":%s,"steps":%s,"stall_limit":3,"replan_limit":5,"critic_rounds":2}}' \
    "$1" "$2" "$3" "$4" > "$S/brief.json"
}
write_brief 5 100 1000 10
T="$CLAUDE_PROJECT_DIR/tx"; mkdir -p "$T"
TR="$T/sess.jsonl"
{
  echo '{"type":"assistant","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":2,"output_tokens":3}}}'
  echo 'not json at all'
  echo '{"type":"assistant","message":{"id":"m2","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":1}}}'
} > "$TR"
out="$(budget --transcript "$TR")"; out="${out//$'\r'/}"
# m1: 2+3; m2: 1+1+cache_creation 1 (cache_read 2 excluded from `tokens`, counted in tokens_total)
expect_contains "tokens summed from transcript (cache reads excluded)" '"tokens": 8,' "$out"
expect_contains "cache_read_tokens summed" '"cache_read_tokens": 2,' "$out"
expect_contains "tokens_total includes cache reads" '"tokens_total": 10,' "$out"
expect_contains "tokens exhausted" '"exhausted": ["tokens"]' "$out"
expect_contains "limits echoed" '"steps": 10' "$out"
out="$(budget --transcript "$TR" --exhausted-only)"; out="${out//$'\r'/}"
[ "$out" = "tokens" ] && ok "--exhausted-only prints tokens" || bad "--exhausted-only prints tokens (got '$out')"
expect_exit "missing transcript is skipped" 0 budget --transcript "$T/nope.jsonl"
expect_contains "missing transcript counts 0 tokens" '"tokens": 0' "$OUT"

# sibling subagent transcript is included
echo '{"type":"assistant","message":{"id":"s1","model":"claude-haiku-4-5","usage":{"input_tokens":4,"output_tokens":1}}}' > "$T/sess-sub1.jsonl"
echo '{"type":"assistant","message":{"id":"x1","usage":{"input_tokens":1000,"output_tokens":0}}}' > "$T/other.jsonl"
out="$(budget --transcript "$TR")"; out="${out//$'\r'/}"
expect_contains "sibling transcript summed, unrelated ignored" '"tokens": 13,' "$out"
rm -f "$T/sess-sub1.jsonl" "$T/other.jsonl"

# steps over limit
write_brief 1000000 100 1000 10
echo 11 > "$S/steps"
out="$(budget --exhausted-only)"; out="${out//$'\r'/}"
[ "$out" = "steps" ] && ok "steps 11/10 exhausted" || bad "steps 11/10 exhausted (got '$out')"

# near exhaustion (>= 85% of a limit, not yet over): the lead's cue to wrap up with a PR instead of being cut off
echo 9 > "$S/steps"
out="$(budget)"; out="${out//$''/}"
expect_contains "steps 9/10: near lists steps" '"near": ["steps"]' "$out"
expect_contains "steps 9/10: not exhausted" '"exhausted": []' "$out"
echo 3 > "$S/steps"
out="$(budget)"; out="${out//$''/}"
expect_contains "steps 3/10: near is empty" '"near": []' "$out"
echo 11 > "$S/steps"
out="$(budget)"; out="${out//$''/}"
expect_contains "steps 11/10: exhausted, not near" '"near": []' "$out"

# PreToolUse gating while exhausted
expect_exit "exhausted: Bash denied" 2 hook budget.sh "$(pre_bash "npm test")"
expect_contains "deny reason names budget" "budget exhausted (steps)" "$OUT"
expect_exit "exhausted: Write docs/REPORT.md allowed" 0 hook budget.sh "$(pre_file Write "/w/repo/docs/REPORT.md")"
expect_exit "exhausted: Edit docs/RUN_STATE allowed" 0 hook budget.sh "$(pre_file Edit "docs/RUN_STATE")"
expect_exit "exhausted: Write src/a.ts denied" 2 hook budget.sh "$(pre_file Write "src/a.ts")"
expect_exit "exhausted: Write mydocs/REPORT.md denied" 2 hook budget.sh "$(pre_file Write "mydocs/REPORT.md")"
expect_exit "exhausted: Read allowed" 0 hook budget.sh "$(pre_file Read "src/a.ts")"
expect_exit "exhausted: Grep allowed" 0 hook budget.sh '{"hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"x"}}'

# not exhausted: everything allowed, no stdout
echo 3 > "$S/steps"
expect_exit "within budget: Bash allowed" 0 hook budget.sh "$(pre_bash "npm test" "$TR")"
[ -z "$OUT" ] && ok "allow prints nothing" || bad "allow prints nothing (got '$OUT')"

# PostToolUse increments steps and reports
out="$(hook budget.sh '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}')"
out="${out//$'\r'/}"
[ "$(cat "$S/steps")" = "4" ] && ok "PostToolUse increments steps 3 -> 4" || bad "PostToolUse increments steps (got $(cat "$S/steps"))"
expect_contains "additionalContext event" '"hookEventName": "PostToolUse"' "$out"
expect_contains "additionalContext BUDGET" 'BUDGET tokens=' "$out"
expect_contains "additionalContext steps" 'steps=4/10' "$out"

# fail closed on malformed input
expect_exit "garbage stdin fails closed" 2 hook budget.sh "not json"
expect_exit "empty stdin fails closed" 2 hook budget.sh ""
expect_exit "missing tool_name fails closed" 2 hook budget.sh '{"hook_event_name":"PreToolUse"}'

# wall clock
write_brief 1000000 100 60 1000
"$QS_PYTHON" -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(minutes=90)).strftime("%Y-%m-%dT%H:%M:%SZ"))' | tr -d '\r' > "$S/started_at"
out="$(budget --exhausted-only)"; out="${out//$'\r'/}"
[ "$out" = "wall_clock_min" ] && ok "90 min elapsed vs 60 exhausts wall_clock_min" || bad "wall_clock_min exhausted (got '$out')"
# --- overseer role: its tool calls are neither gated nor counted ---
write_brief 1000000 100 1000 10; echo 99 > "$S/steps"
expect_exit "overseer role: exhausted Bash still allowed" 0 env QS_ROLE=overseer bash "$ROOT/scripts/hooks/budget.sh" <<< "$(pre_bash "tail -n 20 docs/ledgers/progress.jsonl")"
QS_ROLE=overseer bash "$ROOT/scripts/hooks/budget.sh" <<< '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}' >/dev/null 2>&1
[ "$(tr -dc '0-9' < "$S/steps")" = "99" ] && ok "overseer role: steps not counted" || bad "overseer role: steps=$(cat "$S/steps")"

# --- transcript path memory: the hook remembers the transcript path across calls ---
write_brief 1000000 100 1000 1000; echo 0 > "$S/steps"
rm -f "$S/transcript_path"

# PostToolUse with a non-empty transcript_path stores it verbatim
hook budget.sh '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{},"transcript_path":"'"$TR"'"}' >/dev/null
[ "$(cat "$S/transcript_path" 2>/dev/null)" = "$TR" ] && ok "PostToolUse stores transcript_path" || bad "PostToolUse stores transcript_path (got '$(cat "$S/transcript_path" 2>/dev/null)')"

# PreToolUse with a non-empty transcript_path also stores it (different path)
OTHER="$T/other2.jsonl"
echo '{"type":"assistant","message":{"id":"o1","model":"claude-sonnet-5","usage":{"input_tokens":7,"output_tokens":0}}}' > "$OTHER"
hook budget.sh "$(pre_file Read "src/a.ts" "$OTHER")" >/dev/null
[ "$(cat "$S/transcript_path")" = "$OTHER" ] && ok "PreToolUse stores transcript_path" || bad "PreToolUse stores transcript_path (got '$(cat "$S/transcript_path")')"

# a call whose transcript_path is the empty string does not clobber the stored value
hook budget.sh "$(pre_bash "npm test" "")" >/dev/null
[ "$(cat "$S/transcript_path")" = "$OTHER" ] && ok "empty transcript_path does not clobber stored value" || bad "empty transcript_path clobbered stored value (got '$(cat "$S/transcript_path")')"

# a call with no transcript_path key at all also does not clobber the stored value
hook budget.sh '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}' >/dev/null
[ "$(cat "$S/transcript_path")" = "$OTHER" ] && ok "missing transcript_path does not clobber stored value" || bad "missing transcript_path clobbered stored value (got '$(cat "$S/transcript_path")')"

# budget.py with no --transcript falls back to the stored path and sums the same tokens
printf '%s' "$TR" > "$S/transcript_path"
# elapsed_min is dropped from the comparison: the two calls are seconds apart and can straddle a 0.1-minute boundary
strip_elapsed() { sed -E 's/"elapsed_min": [0-9.]+, //'; }
with_flag="$(budget --transcript "$TR" | strip_elapsed)"; with_flag="${with_flag//$'\r'/}"
without_flag="$(budget | strip_elapsed)"; without_flag="${without_flag//$'\r'/}"
[ "$with_flag" = "$without_flag" ] && ok "budget.py falls back to stored transcript_path" || bad "budget.py fallback mismatch ('$without_flag' vs '$with_flag')"
expect_contains "fallback sums the fixture transcript" '"tokens": 8,' "$without_flag"

# neither --transcript nor a stored transcript_path file: still works, reports 0 tokens
rm -f "$S/transcript_path"
out="$(budget)"; out="${out//$'\r'/}"
expect_contains "no transcript anywhere: 0 tokens" '"tokens": 0' "$out"
# --- cache reads: excluded from `tokens` (the budget dimension), priced in cost_usd, reported separately ---
write_brief 50 100 1000 1000; echo 0 > "$S/steps"; rm -f "$S/started_at"
CR="$T/cache.jsonl"
echo '{"type":"assistant","message":{"id":"c1","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}' > "$CR"
out="$(budget --transcript "$CR")"; out="${out//$'\r'/}"
expect_contains "cache fixture: tokens = input + output + cache_creation" '"tokens": 35,' "$out"
expect_contains "cache fixture: cache_read_tokens reported" '"cache_read_tokens": 100,' "$out"
expect_contains "cache fixture: tokens_total sums all four" '"tokens_total": 135,' "$out"
# sonnet: (10*3 + 5*15 + 100*3*0.1 + 20*3*1.25) / 1e6 = 0.00021 -> rounded to 4 places
expect_contains "cache fixture: cost prices reads at 10% and creation at 125%" '"cost_usd": 0.0002,' "$out"
expect_contains "cache fixture: 35 < 50 not exhausted" '"exhausted": []' "$out"
out="$(budget --transcript "$CR" --exhausted-only)"; out="${out//$'\r'/}"
[ -z "$out" ] && ok "cache fixture: --exhausted-only prints nothing at limit 50" || bad "cache fixture: --exhausted-only at 50 (got '$out')"
write_brief 30 100 1000 1000
out="$(budget --transcript "$CR" --exhausted-only)"; out="${out//$'\r'/}"
[ "$out" = "tokens" ] && ok "cache fixture: --exhausted-only prints tokens at limit 30" || bad "cache fixture: --exhausted-only at 30 (got '$out')"
out="$(hook budget.sh '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{},"transcript_path":"'"$CR"'"}')"
out="${out//$'\r'/}"
expect_contains "cache fixture: BUDGET line shows tokens=35/30" 'BUDGET tokens=35/30' "$out"
rm -f "$S/transcript_path"
finish
