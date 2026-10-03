# Runbook: operating a quickship run

This is for the person who started `bash scripts/run.sh` and wants to know what is on disk, how to intervene, and what a failure means. The contracts behind every file are in `design/contracts.md`.

## Where state lives

Two places. Runtime state is gitignored and local to the checkout; mission state is committed and travels with the PR.

### `.claude/state/` (runtime, gitignored)

| File | Written by | What it is |
|---|---|---|
| `brief.json` | `brief.py validate` | The validated brief. Its presence means a run is active; hooks are no-ops without it. |
| `started_at` | `brief.py validate` (once) | Wall-clock start, used by `budget.py`. |
| `steps` | `hooks/budget.sh` | Tool-call counter across the lead and its subagents. |
| `tier` | lead via `ledger.py tier` | `plan` (read-only) or `act`. |
| `current_step.json` | lead via `ledger.py step-start` | Step id and declared legs for the task in flight. |
| `legs/<step-id>` | `hooks/guard.sh` | Legs a step has used (`untrusted_content`, `outbound`), for the trifecta rule. |
| `idem.jsonl` | `hooks/idem.sh` | Every `git push` and `gh pr create` with its step and exit code. A repeat is denied. |
| `cancel`, `force_replan` | overseer or you | Flag files; existence is the signal. |
| `session_id`, `transcript_path`, `last_run.json` | `run.sh`, `hooks/budget.sh` | What `run.sh` needs to resume the same session. |
| `restarts`, `stop_attempts` | `run.sh`, `hooks/stop.sh` | Restart and refused-stop counters. |
| `hook_log` | `hooks/guard.sh` | One line per tool call: time, tool, argument. Denials are in the session output and `last_run.json`. |
| `overseer.log` | `run.sh` | Combined output of every overseer tick. |

### `docs/` (committed)

| File | What it is |
|---|---|
| `ledgers/task.json` | Task ledger: goal, plan with per-task status (`pending`, `dispatched`, `merged`, `failed`, `skipped`), facts, assumptions, blocked steps, replan and stall counts. |
| `ledgers/progress.jsonl` | Append-only event log, one JSON object per line: `dispatched`, `merged`, `failed`, `timeout`, `assumption`, `blocked`, `replan`, `stall`, `criteria`, `note`. |
| `ledgers/criteria.json` | Last `check_criteria.py` result: one entry per criterion with `pass`, `fail` or `deferred`. |
| `plan.md` | The planner's task list and assumptions. |
| `decisions.md` | Human-readable decision log, one row per merge, assumption or blocked step. Append only. |
| `overseer.md` | Dated overseer notes. |
| `RUN_STATE` | One line of JSON once the run is terminal. |
| `REPORT.md` | The report. Written last. |
| `runs/<at>-<slug>/` | Archived `REPORT.md`, `RUN_STATE`, `plan.md` and `ledgers/` from earlier missions. |

## Watching a run

The lead's output goes to `.claude/state/last_run.json` as a single JSON result when it returns, so the live view is the ledgers:

```bash
tail -f docs/ledgers/progress.jsonl
python3 scripts/budget.py            # tokens, cost, elapsed minutes, steps, and which limits are exhausted
python3 scripts/overseer_status.py   # what the overseer sees: ledger summary, progress tail, budget, flags
tail .claude/state/hook_log
```

`run.sh` prints `run: lead exit=<n> state=<RUN_STATE or none>` when the lead returns.

## Resume after a crash or kill

Run the same command again:

```bash
bash scripts/run.sh
```

What happens:

1. The brief is re-validated and a stale terminal run from a different goal is archived.
2. If `docs/RUN_STATE` is already terminal, `run.sh` prints it and exits 0.
3. `restarts` is incremented. Before restart `n` it sleeps `2^n` seconds (`QS_SLEEP` overrides). At five restarts it writes `SAFE_STOP` and exits 3.
4. If `session_id` exists the lead is resumed with `--resume`. If the session is gone, the lead starts fresh at step 1 of the lead loop and rebuilds from `docs/ledgers/task.json`: `merged` tasks stay done, `dispatched` tasks reuse any existing worktree and branch.
5. Pushes and PRs already in `idem.jsonl` are denied if repeated, so a resumed run never opens a second PR.

If the lead was killed before it returned a JSON result, `run.sh` recovers the session id from the transcript path the budget hook recorded.

## Cancel by hand

```bash
touch .claude/state/cancel
```

From the next tool call the guard allows only `Read`, `Glob`, `Grep` and writes to `docs/REPORT.md` and `docs/RUN_STATE`. The lead sees the flag at its next budget check, skips to synthesis, writes the report and ends in `SAFE_STOP`. The overseer creates the same flag on its own when the replan limit is hit, nothing has progressed for 45 minutes, or the same denied command repeats five times.

To stop the processes outright, kill `run.sh` (the overseer loop dies with it via its exit trap). The run is then resumable as above.

## Force a replan

```bash
touch .claude/state/force_replan
```

At its next check the lead deletes the flag, runs `ledger.py replan` (which bumps `replan_count`, resets `stall_count`, and exits 3 past `replan_limit`, which ends the run in `SAFE_STOP`), and re-runs the planner with the stall reason. The planner must invalidate disproved facts and change the approach, not reissue the same plan.

## Raise a budget mid-run

Edit the `budgets` block in `BRIEF.yaml`, then re-validate so `brief.json` picks it up:

```bash
python3 scripts/brief.py validate
```

The hooks and `budget.py` read `brief.json` on every call, so the new limit applies from the next tool call. `started_at` is not reset, so raising `wall_clock_min` extends from the original start. If the budget hook had already locked the run down (only report writes allowed), the lock lifts as soon as the dimension is under its limit again.

Goal, deliverables and criteria can be edited the same way, but a changed goal makes the ledgers look stale: `ledger.py archive-stale` compares the goal in `task.json` with the brief and archives a terminal run whose goal differs. For an active run, keep the goal text unchanged.

## Reading the results

`docs/REPORT.md` sections, in order: state, deliverables with the PR URL, criteria table, assumptions, blocked steps, uncompensated side effects (pushed branches, open PR), budget used per dimension, replans with reasons, stalls, overseer notes, gaps. Read "Gaps" first on a `DONE_PARTIAL`.

`docs/ledgers/criteria.json`:

```json
{"results": [{"kind": "test", "status": "pass", "detail": "exit 0"},
             {"kind": "judge", "status": "deferred", "detail": "<rubric>"}],
 "passed": 1, "failed": 0, "deferred": 1}
```

`deferred` is a `judge` criterion: `check_criteria.py` never grades those. The reviewer, acting as critic, grades each one PASS or FAIL in the report's criteria table. It may run the brief's `test` commands and the project's own eval to decide.

`docs/decisions.md` has the one-line reason for every merge and every `BLOCKED` or `ASSUMPTION` row; `docs/ledgers/progress.jsonl` has the same events with timestamps, step ids and per-step token and cost figures where the lead recorded them.

## Archived runs

A merged mission PR carries `docs/RUN_STATE`, `REPORT.md`, `plan.md` and `docs/ledgers/` into the next checkout. When `run.sh` starts a brief whose goal differs from the one in `task.json` and `RUN_STATE` is terminal, `ledger.py archive-stale` moves those files to `docs/runs/<at>-<goal-slug>/` (`at` is the terminal timestamp with `:` replaced by `-`), deletes the runtime state, and rewrites `started_at`. It prints `archived <dir>`; `run.sh` echoes it as `run: previous mission archived ...`. The lead runs the same command at step 1 so a cloud session gets the same behaviour.

Commit the archived directory with the next mission; it is the only record of that run once `docs/` is reused.

## Upgrade the harness in a project

From a newer quickship checkout, run `init.sh` against the project with `--upgrade`:

```bash
bash <quickship>/scripts/init.sh <project> --upgrade
# e.g. from inside the project:  bash ../quickship/scripts/init.sh . --upgrade
```

A harness file is refreshed only if the copy in the project still matches the sha recorded in `.quickship/manifest.sha256` at install time; a file you edited is reported as `skip (modified)` and kept. `CLAUDE.md` is never overwritten once it differs; merge its "Hard rules" and "Lead loop" sections by hand. `--force` overwrites everything except `CLAUDE.md`. `.quickship/VERSION` records the installed harness version. Without `--upgrade` or `--force`, `init.sh` only adds files that are missing.

Run `init.sh` while no mission is active: it never touches `.claude/state/` or `docs/ledgers/`, but a refreshed hook or script changes what the next tool call does.

## Harness self-tests

```bash
bash tests/run.sh
```

In an installed project the gate does not run these self-tests (they take minutes and test the harness, not your code). Run them by hand once after `init.sh` or `init.sh --upgrade`, or set `QS_SELFTEST=1` to make the gate include them.


Runs every `tests/*.sh` in parallel (`QS_TEST_JOBS` sets the width), prints each file's output in name order, and exits 0 only when all pass. No test calls an LLM; `overseer.sh` is tested with a stub `claude` on `PATH`. Tests never touch the repo's own `.claude/state`; each one sets `CLAUDE_PROJECT_DIR` to a temp dir. `bash scripts/gate.sh` runs the same suite after the secrets scan, lint, test and build. On Windows run both from Git Bash with `QS_PYTHON` pointing at a Python 3.10+ interpreter if `python3` is not on `PATH`. CI runs the suite on Ubuntu and Windows (`.github/workflows/tests.yml`).

## Common failures

| Symptom | Meaning | What to do |
|---|---|---|
| `run: BRIEF.yaml invalid or missing` and exit 2 | The brief failed validation; the line above names the key, e.g. `brief: missing mission.goal` or `brief: unknown kind 'x'`. | Fix the key and re-run. With the built-in reader, check quoting, 2-space indent, and that no `cmd` contains a colon. |
| Tool calls denied with `budget exhausted (<names>)` and `RUN_STATE` says `DONE_PARTIAL` | A budget dimension hit its limit. The hook let the lead write only the report. | Read "Gaps" in the report. Raise the limit in `BRIEF.yaml`, re-validate, remove `docs/RUN_STATE`, and re-run to continue from the ledgers; or merge the partial PR. |
| `run: restart limit reached, wrote SAFE_STOP` and exit 3 | The lead returned without a terminal state five times. | Look at `last_run.json` and `hook_log` for the repeated failure (often a denied command or a hook erroring). Fix the cause, delete `.claude/state/restarts` and `docs/RUN_STATE`, re-run. |
| `stall` lines in `progress.jsonl`, then `replan` | `ledger.py stall-check` saw the same slug dispatched twice with the same goal, an unchanged state hash, three identical failures, or a timeout. The lead replanned. | Nothing, unless replans keep repeating. Past `replan_limit` the run ends in `SAFE_STOP`; the report says why each replan happened. |
| `guard: denied (<reason>)` lines in the lead output | The hook refused a hard-rule violation, a write in the plan tier, a trifecta leg clash, or `cd` before `git`. The lead records it as blocked and routes around it. | Nothing for a one-off. Repeats of the same denial mean the lead is stuck; the overseer cancels after five in a row. |
| `already executed at <ts> (exit <n>); use the recorded result` | The idempotency hook refused a second push or PR create in the same step. | Nothing. The first result stands; check `idem.jsonl`. |
| `no terminal RUN_STATE: write docs/RUN_STATE and docs/REPORT.md before stopping` | The Stop hook refused to let the lead end mid-run. After three refusals it writes `SAFE_STOP` itself. | Nothing. If the run ended `SAFE_STOP` with reason `lead ended without terminal state`, re-run to resume. |
| `overseer tick exit=1 is_error=true` in `overseer.log` | An overseer tick failed. The lead keeps running without the watchdog. | Run `bash scripts/overseer.sh` once by hand and read its output. |
| `Ignoring N permissions.allow entries ... workspace has not been trusted` | Expected in a never-trusted folder; `run.sh` passes the allow list with `--allowedTools`. | Nothing. |
| `execvpe(/bin/bash) failed` from PowerShell | `bash` resolved to the WSL stub. | Use `.\run.cmd`, or a Git Bash terminal. |
| `gate: FAIL` with `secrets: possible credential in: <file>` | The gate's secrets scan matched a key format in a tracked or untracked file. | Remove the value, never commit it; if it was real, rotate it. |

## Starting over

Only when you no longer need the current run's report and ledgers:

```bash
rm docs/RUN_STATE && rm -r docs/ledgers .claude/state
```

Then edit `BRIEF.yaml` and run `bash scripts/run.sh`. For a new goal this is not needed: `archive-stale` moves the finished run aside on its own.
