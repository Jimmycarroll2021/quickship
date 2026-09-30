#!/usr/bin/env bash
# scripts/ledger.py: task/progress ledgers, state hash, stall detection, replan budget, step legs.
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"
mkdir -p "$CLAUDE_PROJECT_DIR/docs" "$CLAUDE_PROJECT_DIR/.claude/state"
L="$CLAUDE_PROJECT_DIR/docs/ledgers"; S="$CLAUDE_PROJECT_DIR/.claude/state"
led() { "$QS_PYTHON" "$ROOT/scripts/ledger.py" "$@"; }
q() { local o; o="$(led "$@" 2>&1)"; printf '%s' "${o//$'\r'/}"; }
# jget <file> <python-expr over d>  -> prints the value
jget() { local o; o="$("$QS_PYTHON" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); print($2)" "$1")"; printf '%s' "${o//$'\r'/}"; }
lastline() { tail -n 1 "$L/progress.jsonl"; }
reset() { led init --goal "$1" --force >/dev/null 2>&1; }

# --- init ---
expect_exit "init creates ledgers" 0 led init --goal "Ship the ledger"
if [ -f "$L/task.json" ] && [ -f "$L/progress.jsonl" ]; then ok "both ledger files exist"; else bad "both ledger files exist"; fi
expect_contains "task.json holds the goal" "Ship the ledger" "$(jget "$L/task.json" "d['goal']")"
expect_contains "task.json counters start at 0" "0 0 False" "$(jget "$L/task.json" "d['replan_count'], d['stall_count'], d['is_complete']")"
expect_exit "init again without --force exits 2" 2 led init --goal "again"
expect_exit "init --force succeeds" 0 led init --goal "Ship the ledger" --force
expect_exit "init without --goal exits 2" 2 led init
if grep -q $'\r' "$L/task.json"; then bad "task.json is LF"; else ok "task.json is LF"; fi

# --- stall-check on a fresh ledger ---
expect_exit "stall-check fresh ledger exits 0" 0 led stall-check

# --- task-add / task-set ---
expect_exit "task-add" 0 led task-add add-readme --goal "Write README" --owns README.md,docs/x.md
expect_contains "task-add stores pending task" "add-readme pending ['README.md', 'docs/x.md']" \
  "$(jget "$L/task.json" "d['plan'][0]['slug'], d['plan'][0]['status'], d['plan'][0]['owns']")"
expect_exit "task-add duplicate slug exits 2" 2 led task-add add-readme --goal "dup" --owns a
expect_exit "task-add bad slug exits 2" 2 led task-add Not_Kebab --goal "x" --owns a
expect_exit "task-add slug over 24 chars exits 2" 2 led task-add abcdefghij-abcdefghij-abcd --goal "x" --owns a
h1="$(q hash)"
if printf '%s' "$h1" | grep -Eqx '[0-9a-f]{64}'; then ok "hash is 64 hex"; else bad "hash is 64 hex ($h1)"; fi
if [ "$h1" = "$(q hash)" ]; then ok "hash stable across calls"; else bad "hash stable across calls"; fi
expect_exit "task-set merged with commit" 0 led task-set add-readme merged --branch feat/x--add-readme --commit abc1234
expect_contains "task-set updates status/branch/commit" "merged feat/x--add-readme abc1234" \
  "$(jget "$L/task.json" "d['plan'][0]['status'], d['plan'][0]['branch'], d['plan'][0]['commit']")"
h2="$(q hash)"
if [ "$h1" != "$h2" ]; then ok "hash changes after task-set"; else bad "hash changes after task-set"; fi
expect_exit "task-set bad status exits 2" 2 led task-set add-readme done
expect_exit "task-set unknown slug exits 2" 2 led task-set nope merged

# --- append ---
expect_exit "append dispatched" 0 led append dispatched add-readme "worker sent" --tokens 12 --cost 0.5
line="$(lastline)"
expect_contains "append writes step s001" '"step": "s001"' "$line"
expect_contains "append writes event" '"event": "dispatched"' "$line"
expect_contains "append writes detail" '"detail": "worker sent"' "$line"
expect_contains "append writes tokens" '"tokens": 12' "$line"
if printf '%s' "$line" | grep -Eq '"ts": "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"'; then ok "append writes UTC ts"; else bad "append writes UTC ts: $line"; fi
if printf '%s' "$line" | grep -Eq '"state_hash": "[0-9a-f]{64}"'; then ok "append writes 64-hex state_hash"; else bad "append writes 64-hex state_hash: $line"; fi
expect_contains "append state_hash equals current hash" "$h2" "$line"
expect_exit "append bad event exits 2" 2 led append exploded add-readme "x"
led append note add-readme "second" >/dev/null 2>&1
expect_contains "append second line is s002" '"step": "s002"' "$(lastline)"

# --- hash excludes counters ---
hb="$(q hash)"
led replan >/dev/null 2>&1
if [ "$hb" = "$(q hash)" ]; then ok "hash unchanged by replan"; else bad "hash unchanged by replan"; fi

# --- stall-check rules ---
reset "stall goal"; led task-add t1 --goal "Do t1" --owns a >/dev/null 2>&1
led append dispatched t1 "first" >/dev/null 2>&1
expect_exit "stall-check one dispatch exits 0" 0 led stall-check
led task-set t1 dispatched >/dev/null 2>&1
led append dispatched t1 "second" >/dev/null 2>&1
expect_exit "stall-check two dispatches same slug+goal exits 1" 1 led stall-check
expect_contains "stall-check names the dispatch reason" "dispatched" "$OUT"
expect_contains "stall_count incremented to 1" "1" "$(jget "$L/task.json" "d['stall_count']")"

reset "failed goal"; led task-add t2 --goal "Do t2" --owns b >/dev/null 2>&1
for i in 1 2 3; do led task-set t2 pending --commit "c$i" >/dev/null 2>&1; led append failed t2 "tests red" >/dev/null 2>&1; done
expect_exit "stall-check three identical failed exits 1" 1 led stall-check
expect_contains "stall-check names the failed reason" "failed" "$OUT"

reset "failed differ"; led task-add t3 --goal "Do t3" --owns c >/dev/null 2>&1
for i in 1 2 3; do led task-set t3 pending --commit "c$i" >/dev/null 2>&1; led append failed t3 "error $i" >/dev/null 2>&1; done
expect_exit "stall-check three differing failed exits 0" 0 led stall-check

reset "hash goal"; led task-add t4 --goal "Do t4" --owns d >/dev/null 2>&1
led append note t4 "a" >/dev/null 2>&1; led append note t4 "b" >/dev/null 2>&1
expect_exit "stall-check unchanged state_hash exits 1" 1 led stall-check
expect_contains "stall-check names the hash reason" "state_hash" "$OUT"

reset "timeout goal"; led task-add t5 --goal "Do t5" --owns e >/dev/null 2>&1
led append timeout t5 "worker hung" >/dev/null 2>&1
expect_exit "stall-check timeout exits 1" 1 led stall-check
expect_contains "stall-check names the timeout reason" "timeout" "$OUT"

# --- replan ---
reset "replan goal"
printf '{"budgets": {"replan_limit": 1}}' > "$S/brief.json"
led append timeout t "x" >/dev/null 2>&1; led stall-check >/dev/null 2>&1
expect_contains "stall_count is 1 before replan" "1" "$(jget "$L/task.json" "d['stall_count']")"
expect_exit "replan within limit exits 0" 0 led replan
expect_contains "replan resets stall, bumps replan_count" "0 1" "$(jget "$L/task.json" "d['stall_count'], d['replan_count']")"
expect_contains "replan appends a replan line" '"event": "replan"' "$(lastline)"
expect_exit "replan over limit exits 3" 3 led replan
expect_contains "replan_count is 2" "2" "$(jget "$L/task.json" "d['replan_count']")"
rm -f "$S/brief.json"
expect_exit "replan without brief uses default limit 5" 0 led replan

# --- step-start ---
reset "step goal"; led append note x "one" >/dev/null 2>&1
expect_exit "step-start writes current_step" 0 led step-start add-readme --legs untrusted_content,local_write
expect_contains "current_step has next id, slug, legs" "s002 add-readme ['untrusted_content', 'local_write']" \
  "$(jget "$S/current_step.json" "d['id'], d['slug'], d['legs']")"
expect_exit "step-start untrusted_content+outbound exits 2" 2 led step-start leak --legs untrusted_content,outbound
expect_contains "denied step-start leaves current_step alone" "add-readme" "$(jget "$S/current_step.json" "d['slug']")"

# --- facts-invalidate ---
"$QS_PYTHON" -c "
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding='utf-8'))
d['facts'] = [{'text': 'API uses v2 endpoints', 'source': 'docs', 'ts': '2026-09-30T00:00:00Z', 'valid': True},
              {'text': 'Node 20 required', 'source': 'pkg', 'ts': '2026-09-30T00:00:00Z', 'valid': True}]
open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(d))
" "$L/task.json"
expect_exit "facts-invalidate" 0 led facts-invalidate "v2 endpoints"
expect_contains "facts-invalidate flips only matches" "False True" "$(jget "$L/task.json" "d['facts'][0]['valid'], d['facts'][1]['valid']")"

# --- missing ledger ---
rm -f "$L/task.json"
expect_exit "task-add without task.json exits 2" 2 led task-add x --goal y --owns z
expect_exit "hash without task.json exits 2" 2 led hash
finish
