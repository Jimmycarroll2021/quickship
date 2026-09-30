# quickship runtime contracts

Every script and hook in this repo builds to these contracts. They are the interface between the lead loop in `CLAUDE.md`, the hooks in `scripts/hooks/`, the CLIs in `scripts/`, and the tests in `tests/`. Change a contract here first, then the code.

## Conventions (all scripts)

- Bash for hooks, Python (stdlib only, 3.10+) for CLIs. LF line endings (`.gitattributes` enforces).
- Python resolution in bash: `PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"`. Python on Windows emits CRLF: strip with `out="${out//$'\r'/}"` before parsing its output in bash.
- State dir: `S="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.claude/state"` (gitignored). `CLAUDE_PROJECT_DIR` stays at the main checkout inside a worktree; the hook input `cwd` follows the worktree.
- Every hook reads its JSON from stdin and **fails closed**: malformed or missing input → exit 2 with a one-line reason on stderr. A hook that finds no active run (`$S/brief.json` absent) is a no-op: exit 0.
- Hook outcomes. Deny/block: exit 2 and reason on stderr. Allow: exit 0, no stdout. Add context: exit 0 and print exactly one JSON object `{"hookSpecificOutput":{"hookEventName":"<Event>","additionalContext":"<text>"}}`. Stop block alternative: `{"decision":"block","reason":"..."}` with exit 0.
- Hook input common fields: `hook_event_name`, `tool_name`, `tool_input` (`command` for Bash; `file_path` for Read/Write/Edit/MultiEdit), `tool_response` (PostToolUse only), `cwd`, `transcript_path`, `session_id`, and `source` on SessionStart (`startup|resume|clear|compact|fork`).
- Atomic file writes in Python: write to `<path>.tmp` then `os.replace`.
- Timestamps: ISO 8601 UTC with `Z`, e.g. `2026-09-30T09:00:00Z`.
- Tests: `tests/<name>.sh` sources `tests/lib.sh` and uses `ok`, `bad`, `expect_exit <label> <exit> <cmd...>` (captures combined output in `$OUT`), `expect_contains <label> <needle> <haystack>`, `hook <script-name> <json>` (feeds stdin to `scripts/hooks/<name>`), `tmpdir`, `finish`. Tests never call an LLM and never touch the repo's own `.claude/state`; set `export CLAUDE_PROJECT_DIR="$(tmpdir)"` first. `bash tests/run.sh` runs them all.

## Files

| Path | Written by | Read by |
|---|---|---|
| `BRIEF.yaml` | human, once | `scripts/brief.py` |
| `.claude/state/brief.json` | `brief.py validate` | every hook and script |
| `.claude/state/started_at` | `brief.py validate` (only if absent) | `budget.py` |
| `.claude/state/steps` | `hooks/budget.sh` (PostToolUse) | `budget.py` |
| `.claude/state/tier` | lead (`plan` or `act`) | `hooks/guard.sh` |
| `.claude/state/current_step.json` | lead at dispatch | `hooks/idem.sh`, `hooks/guard.sh` |
| `.claude/state/legs/<step-id>` | `hooks/guard.sh` (PostToolUse) | `hooks/guard.sh` |
| `.claude/state/idem.jsonl` | `hooks/idem.sh` | `hooks/idem.sh` |
| `.claude/state/cancel`, `.claude/state/force_replan` | overseer (existence is the signal) | lead, `hooks/guard.sh` |
| `.claude/state/stop_attempts`, `restarts`, `session_id`, `hook_log` | `hooks/stop.sh`, `run.sh`, `run.sh`, `hooks/guard.sh` | same |
| `docs/ledgers/task.json` | `scripts/ledger.py` | lead, `hooks/anchor.sh`, overseer |
| `docs/ledgers/progress.jsonl` | `scripts/ledger.py append` | lead, overseer |
| `docs/ledgers/criteria.json` | `scripts/check_criteria.py` | lead, report |
| `docs/RUN_STATE` | lead (or `hooks/stop.sh`, `run.sh` on give-up) | `hooks/stop.sh`, `run.sh`, `hooks/budget.sh` |
| `docs/REPORT.md` | lead, last | human |
| `docs/overseer.md` | overseer | lead, report |

## BRIEF.yaml → brief.json

`scripts/brief.py validate [--brief BRIEF.yaml]` parses the YAML (PyYAML if importable, else a built-in reader for the strict subset below), validates, writes `$S/brief.json` and `$S/started_at` (if absent), exit 0. Any missing key, non-positive budget, or unknown `kind` → exit 2, stderr names the key. `scripts/brief.py show` prints brief.json.

Strict YAML subset the built-in reader must accept: block mappings with 2-space indent, scalar values, block lists of scalars (`- item`), and block lists of single-line flow maps (`- {kind: test, cmd: "npm test", expect: 0}`). Strings may be quoted with `"` or `'`. No anchors, multi-line scalars or nested flow.

```yaml
mission:
  goal: "Add a README that describes quickship"
  deliverables:
    - README.md
success_criteria:
  - {kind: test, cmd: "bash tests/run.sh", expect: 0}
  - {kind: file, path: README.md, must_contain: "quickship"}
  - {kind: grep, pattern: "## Lead loop", path: CLAUDE.md}
  - {kind: judge, rubric: "README explains what a Mission Brief is"}
budgets:
  tokens: 5000000
  cost_usd: 40
  wall_clock_min: 480
  steps: 400
  stall_limit: 3
  replan_limit: 5
  critic_rounds: 2
permissions:
  irreversible:
    default: skip-and-record
    allow:
      - "git push origin mission/*"
      - "gh pr create*"
ambiguity_policy: choose-default-and-record
```

brief.json is the same structure as JSON. Required: `mission.goal` (string), `mission.deliverables` (list), `success_criteria` (list, each with `kind` in `test|file|grep|judge` and that kind's fields: test → `cmd`, `expect` (int, default 0); file → `path`, optional `must_contain` regex; grep → `pattern`, `path`; judge → `rubric`), `budgets` (all seven integers/floats > 0; defaults: stall_limit 3, replan_limit 5, critic_rounds 2), `permissions.irreversible.default` in `skip-and-record|allow`, `permissions.irreversible.allow` list of shell-glob patterns, `ambiguity_policy` = `choose-default-and-record`.

## Ledgers

`docs/ledgers/task.json`:
```json
{"goal": "...", 
 "plan": [{"slug": "add-readme", "goal": "...", "owns": ["README.md"], "status": "pending", "branch": "", "commit": ""}],
 "facts": [{"text": "...", "source": "...", "ts": "...", "valid": true}],
 "assumptions": [{"text": "...", "ts": "..."}],
 "blocked": [{"step": "...", "rule": "...", "ts": "..."}],
 "replan_count": 0, "stall_count": 0, "is_complete": false}
```
`status` ∈ `pending|dispatched|merged|failed|skipped`. Slugs are kebab-case, max 24 chars.

`docs/ledgers/progress.jsonl`, one object per line, append-only:
```json
{"ts": "...", "step": "s007", "slug": "add-readme", "event": "dispatched", "detail": "...", "state_hash": "<sha256 hex>", "tokens": 0, "cost_usd": 0.0}
```
`event` ∈ `dispatched|merged|failed|timeout|assumption|blocked|replan|stall|criteria|note`. `step` is `s` plus a zero-padded 3-digit counter, unique per run.

`scripts/ledger.py` subcommands (all exit 0 on success unless stated; 2 on bad args or missing files):
- `init --goal "<text>"` creates both ledgers (fails with exit 2 if task.json exists unless `--force`).
- `task-add <slug> --goal "<text>" --owns a,b,c` appends a pending task.
- `task-set <slug> <status> [--branch b] [--commit sha]`.
- `append <event> <slug> "<detail>" [--tokens N] [--cost F]` writes one progress line with the current `hash` and the next step id.
- `hash` prints sha256 of task.json with `replan_count`, `stall_count` and timestamps excluded.
- `stall-check` exits 1 and increments `stall_count` when any of: the last two progress lines with event `dispatched` have the same slug and the same task goal; the `state_hash` of the last progress line equals the one before it; the last three `failed` lines share the same `detail`; the last line is a `timeout`. Exit 0 otherwise. Prints the reason.
- `replan` increments `replan_count`, resets `stall_count` to 0, writes a `replan` progress line; exit 3 if the new `replan_count` exceeds `budgets.replan_limit` from brief.json.
- `step-start <slug> --legs a,b` writes `$S/current_step.json` with the next step id; exit 2 if legs contain both `untrusted_content` and `outbound`.
- `facts-invalidate "<substring>"` marks matching facts `valid: false`.
- `tier [plan|act]` sets or prints `$S/tier` (the lead must never write it with a shell redirect: Claude Code protects `.claude/` paths).

## Budgets

`scripts/budget.py [--transcript <path>] [--exhausted-only]` reads brief.json (exit 2 if absent), `started_at`, `steps`, and sums usage from the transcript JSONL (each line may have `message.usage` with `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, and `message.model`) plus any `*.jsonl` files in the same directory whose name starts with the transcript's basename (subagent transcripts, best effort). Cost = tokens × per-model rates from a small built-in table (USD per million: opus in 15 / out 75; sonnet in 3 / out 15; haiku in 1 / out 5; cache read at 10% of input; unknown model uses sonnet). Prints:
```json
{"tokens": 0, "cost_usd": 0.0, "elapsed_min": 0.0, "steps": 0, "limits": {"tokens": 0, "cost_usd": 0, "wall_clock_min": 0, "steps": 0}, "exhausted": []}
```
`exhausted` lists every dimension at or over its limit. With `--exhausted-only` prints only the comma-separated names (empty output when none). Exit 0 in both forms.

`scripts/hooks/budget.sh` runs on PreToolUse and PostToolUse (matcher `.*`). No-op without brief.json. PostToolUse: increment `$S/steps`, then print additionalContext `BUDGET tokens=<n>/<limit> cost=<f>/<limit> min=<f>/<limit> steps=<n>/<limit>`. PreToolUse: if `exhausted` is non-empty, allow only `Read`, `Glob`, `Grep`, and `Write`/`Edit` whose `file_path` ends with `docs/REPORT.md` or `docs/RUN_STATE`; deny everything else with stderr `budget exhausted (<names>): write docs/RUN_STATE {"state":"DONE_PARTIAL"} and docs/REPORT.md, then stop`.

## Termination

`docs/RUN_STATE` is exactly one line: `{"state": "DONE|DONE_PARTIAL|SAFE_STOP|HALT", "reason": "...", "at": "..."}`.

A merged mission PR carries `docs/RUN_STATE`, `REPORT.md`, `plan.md` and `docs/ledgers/` into the next mission's checkout. `ledger.py archive-stale` (run by `run.sh` after the brief validates, and by the lead at step 1) prints `current` when there is no terminal RUN_STATE or its ledgers carry the brief's goal; otherwise it moves those files to `docs/runs/<at>-<goal-slug>/`, deletes the runtime state (`session_id`, `steps`, `restarts`, `stop_attempts`, `idem.jsonl`, `current_step.json`, `tier`, `cancel`, `force_replan`, `transcript_path`, `last_run.json`, `legs/`), rewrites `started_at`, and prints `archived <dir>`.

`scripts/hooks/stop.sh` (Stop hook): if brief.json is absent → `exec bash "$ROOT/scripts/gate.sh"` (ROOT = `CLAUDE_PROJECT_DIR`). If a run is active and RUN_STATE is missing or not terminal: increment `$S/stop_attempts`; on attempts 1 and 2 block with reason `no terminal RUN_STATE: write docs/RUN_STATE and docs/REPORT.md before stopping`; on attempt 3 write `{"state":"SAFE_STOP","reason":"lead ended without terminal state","at":...}` yourself and allow. If RUN_STATE is `HALT` → exit 0 without the gate. Otherwise run the gate and pass its exit through.

## Idempotency

`scripts/hooks/idem.sh` runs on PreToolUse and PostToolUse for Bash. Matches commands containing `git push` or `gh (pr|issue|release) create`; every other command → exit 0 immediately. Key = sha256 of `<step id from current_step.json, or "nostep">\n<command with whitespace runs collapsed>`. Ledger `$S/idem.jsonl` lines: `{"key": "...", "step": "s007", "cmd": "...", "status": "pending|done", "exit": 0, "ts": "..."}`. PreToolUse: if a line with this key has `status: done` → exit 2 with stderr `already executed at <ts> (exit <n>); use the recorded result, do not retry`; else append `pending`. PostToolUse: append a `done` line with the exit code from `tool_response` (best effort; 0 if absent).

## Anchoring

`scripts/hooks/anchor.sh` (SessionStart, matcher `compact|resume`): no-op without brief.json. Prints additionalContext (under 9000 characters) containing: `<mission-brief>` with goal, deliverables, success_criteria one per line, budgets, permissions; `<plan>` as a table slug|status|goal from task.json; `<assumptions>`, `<blocked>` lists; the `budget.py` one-line summary; `flags: cancel=<yes|no> force_replan=<yes|no>`; and the sentence `You never ask a question. Continue the lead loop in CLAUDE.md from step 1.`

## Criteria

`scripts/check_criteria.py [--cwd <dir>]` reads brief.json, runs each criterion: `test` → subprocess `bash -c cmd` with a 600 s timeout, pass when exit == expect; `file` → path exists and, if `must_contain`, the regex matches the content; `grep` → regex matches the file; `judge` → `{"status": "deferred"}`. Writes `docs/ledgers/criteria.json` as `{"results": [{"kind": ..., "status": "pass|fail|deferred", "detail": "..."}], "passed": n, "failed": n, "deferred": n}`. Exit 0 when `failed == 0`, else 2.

## Overseer

`scripts/overseer.sh` runs one overseer tick: `claude -p "$(cat .claude/agents/overseer.md)" --max-turns 8 --permission-mode acceptEdits --permission-prompts none --allowedTools "Read,Glob,Grep,Edit(docs/overseer.md),Edit(.claude/state/force_replan),Edit(.claude/state/cancel),Bash(python3 scripts/budget.py *),Bash(python scripts/budget.py *),Bash(tail *)" --output-format json`, exits 0 when the JSON result has `is_error: false`. It must be testable with a stub `claude` on PATH. `.claude/agents/overseer.md` tells the overseer: read both ledgers, the progress tail, `budget.py` output and `docs/decisions.md`; append a dated note to `docs/overseer.md`; create `.claude/state/force_replan` when the last 3 progress lines share slug and state_hash; create `.claude/state/cancel` when `replan_count >= replan_limit`, when no progress line is newer than 45 minutes, or when `hook_log` shows the same denied command 5 times in a row; never do anything else.
