# Runbook: operating a quickship v0.3 run

This is for the person who started `bash scripts/run.sh` and wants to know what is on disk, how to intervene, and what a failure means. The contracts behind every file are in [design/contracts.md](design/contracts.md).

## Before a mission

Install or upgrade the harness in a trusted development project, never in a sensitive original or anything live. Resolve anything listed in `.quickship/conflicts`, edit and commit `BRIEF.yaml` together with the installed harness files, then check the setup without spending anything:

```bash
python scripts/preflight.py
```

Preflight checks versions, authentication, the brief and its quality configuration, and the committed harness. It makes no model calls and no account changes. Requirements:
- Claude Code 2.1.288 or newer.
- Git, Python 3.10 or newer, `gh`, and bash 4 or newer. On Windows, use Git Bash or the `.cmd` wrappers.
- A git author identity, and an `origin` that points at github.com.

For subscription-only work, check that paid extra usage is disabled. quickship never changes billing.

## Where state lives

Two places. Runtime state is gitignored and local to the checkout. Mission state is committed and travels with the PR.

### `.claude/state/` (runtime, gitignored)

| File | Written by | What it is |
|---|---|---|
| `controller.json` | the controller | The frozen brief, harness hashes, absolute deadline, auth method and repository for this run. Its presence means a v0.3 run exists. |
| `runtime.sqlite3` | the controller and hooks | Serialized counters and records: launches, publishing reservations, the controller's report rendering. |
| `brief.json`, `started_at` | `brief.py validate` | The validated brief and the wall-clock start. |
| `steps` | `hooks/budget.sh` | Tool-call counter across the lead and its subagents. |
| `session_id`, `transcript_path`, `last_run.json` | the controller, `hooks/budget.sh` | What the controller needs to resume the same session. |
| `tier`, `current_step.json` | lead via `ledger.py` | Plan or act tier, and the step in flight. Subagents bind to their registered step. |
| `cancel`, `force_replan` | the overseer or you | Flag files. Existence is the signal. |
| `hook_log` | `hooks/guard.sh` | One line per tool call, plus `DENY` lines with the reason. |
| `overseer-process.log` | the controller | Output of the overseer loop. |
| `program.tsv`, `program-current`, `program-mark`, `program-baseline` | `program.sh` | Which chained missions finished, in what state, on which branch, and which one is in progress; the marker and copy it uses to tell this mission's RUN_STATE from a predecessor's. |

### `docs/` (committed)

| File | What it is |
|---|---|
| `RESULT.json` | What the lead submitted when it stopped: `READY`, `DONE_PARTIAL`, `SAFE_STOP` or `HALT`, with a reason. A claim, not the outcome. |
| `COMPLETION.json` | The controller's verdict and evidence: gate, criteria, security verdict for the final commit, publication record, and `retryable` (whether a plain rerun can resume the run). |
| `RUN_STATE` | One line of JSON with the verified state. Written only by the controller. |
| `REPORT.md` | The report. The controller's verified-outcome heading sits on top of the lead's details. |
| `ledgers/task.json`, `ledgers/progress.jsonl`, `ledgers/criteria.json` | Task ledger, append-only event log, and the last criteria result. |
| `plan.md`, `decisions.md`, `overseer.md` | The planner's plan, the decision log (append only), and dated overseer notes. |
| `runs/<at>-<slug>/` | Archived documents and ledgers from earlier runs. |

## Watching a run

```bash
tail -f docs/ledgers/progress.jsonl
python scripts/budget.py            # tokens, cost, elapsed minutes, steps, exhausted and near limits
python scripts/overseer_status.py   # what the overseer sees: ledger summary, budget, flags, repeated denials
tail .claude/state/hook_log
```

The lead and the overseer are child processes owned by the controller. On cancellation or the deadline, the controller ends the whole process tree it owns. Local logs can contain private project information, so don't share them raw.

## How a run finishes

The lead submits `docs/RESULT.json` and its report, then stops. The controller then checks everything itself:
- it reruns the gate and the objective criteria
- it requires every deliverable, evidenced judge grades, a security pass for the final commit, and a clean tree
- it confirms the active harness and brief are unchanged

Only then does it push the mission branch, open the PR, and verify the remote head and base. It records the result in `RUN_STATE`, `COMPLETION.json` and the report heading.

| `run.sh` exit code | Meaning |
|---|---|
| 0 | Verified `DONE`. |
| 2 | Preflight or brief failure, before any model work. Also an `--archive` that was refused. |
| 3 | `DONE_PARTIAL` or `SAFE_STOP`. |
| 4 | `HALT`: a policy or integrity violation. Review before doing anything else. |
| 5 | `ERROR`: the controller or its verification failed. |

`DONE_PARTIAL` doesn't promise a PR. After a publishing error, check the uncompensated side effects the report lists, such as a pushed branch. A rerun reconciles against GitHub before it publishes again.

## Resume after a crash or interruption

Run the same command again:

```bash
bash scripts/run.sh
```

The controller keeps the session, the ledgers, the launch counter and the original deadline. Ctrl+C records `SAFE_STOP` and keeps all of them too. Five launches are allowed in total, with exponential backoff between them (`QS_SLEEP` overrides). A verified `DONE` is never published again, and `HALT` needs your review. If the saved session is gone, the controller reports it rather than starting a duplicate mission.

Inside a mission chain, `program.sh` reruns a mission in place when its lead crashed or the controller was interrupted (`"retryable": true` in `COMPLETION.json`), within the same five-launch limit. A mission that ends in any other state, or exits non-zero without a fresh state (`FAILED rc=<n>` in `docs/PROGRAM.md`), stops the chain with exit 3.

## Cancel by hand

```bash
touch .claude/state/cancel
```

The controller ends the lead and the overseer, and the run finishes in `SAFE_STOP` with its report. The overseer creates the same flag on its own when the replan limit is hit, nothing has progressed for 45 minutes, or the same denied command repeats five times. If no controller is running when you create the flag, run `bash scripts/run.sh` once so it can record `SAFE_STOP`. That briefly starts the lead and counts as one of the five launches. Archive the run before you start again, because the archive also clears the flag.

## Force a replan

```bash
touch .claude/state/force_replan
```

At its next check the lead deletes the flag, runs `ledger.py replan`, and reruns the planner with the reason. `replan` bumps `replan_count` and resets `stall_count`. Past `replan_limit` it exits 3, which ends the run in `SAFE_STOP`. The planner must drop disproved facts and change the approach, not reissue the same plan.

## Raise a budget

Edit only the `budgets` block in `BRIEF.yaml`, commit it, and run `bash scripts/run.sh` again. When nothing but the budgets changed, the controller keeps the same run and the same session. It recomputes the deadline as the original start plus the new `wall_clock_min`, and it continues. This works for a run that ended `DONE_PARTIAL` because a limit ran out.

## Change the brief or start over

Any other change to the brief of an unfinished run is refused, because the controller froze that brief when the run started. Archive the run first:

```bash
bash scripts/run.sh --archive
```

This works for a finished run in any state: `DONE`, `DONE_PARTIAL`, `SAFE_STOP`, `HALT` or `ERROR`. It moves the run's documents and ledgers to `docs/runs/<at>-<slug>/`, clears the runtime state including the session and any flags, and prints `archived <dir>`. It makes no model call. With no run at all it prints `run: nothing to archive` and exits 0. If the run isn't finished, it refuses with exit 2 and says so. Cancel the run first, run it once to let it stop, then archive.

After a verified `DONE`, a brief with a new goal starts fresh on its own. The finished run is archived automatically.

Commit the archived directory with the next mission, because it is the only record of that run once `docs/` is reused.

Active state left by quickship v0.2 is incompatible with the v0.3 controller and isn't migrated automatically. Keep its report, session and ledgers, then archive it with `--archive` or move it by hand.

## Reading the results

Read `docs/COMPLETION.json` and `docs/REPORT.md` before judging success. The report's top section is the controller's verdict. Below it come the lead's details:
- deliverables, criteria and assumptions
- blocked steps and uncompensated side effects
- budget used, replans, stalls and overseer notes
- gaps

Read "Gaps" first on a `DONE_PARTIAL`. `docs/decisions.md` has a one-line reason for every merge and every `BLOCKED` or `ASSUMPTION` row. `docs/ledgers/progress.jsonl` has the same events with timestamps and step ids.

## Quality checks and skips

A required check that's missing fails the gate. Configure `quality.lint`, `quality.test` and `quality.build` in the brief, as a command or as `{skip: "reason"}`. The docs profile has to be selected explicitly, and it rejects application-code changes. A Python build counts as not applicable only when no build system is declared. Project test and dependency commands are trusted code that runs with your access.

## Upgrade the harness in a project

From a newer quickship checkout, run `init.sh` with `--upgrade` while no mission is active:

```bash
bash <quickship>/scripts/init.sh <project> --upgrade
```

A file is refreshed only if it still matches the checksum recorded at install time. Files you modified, and a custom `CLAUDE.md` or settings, are kept and listed in `.quickship/conflicts`. Reconcile each one, then rerun the installer. An incomplete upgrade keeps the previous version and can't pass preflight. `--force` overwrites everything except a custom `CLAUDE.md`. When replacing a v0.2 installation, review v0.3's exit codes, its quality requirements and controller-owned publishing first.

## Harness self-tests

```bash
bash tests/run.sh
```

The suite runs every `tests/*.sh` in parallel (`QS_TEST_JOBS` sets the width) and exits 0 only when all pass. No test calls a model or GitHub. In an installed project the gate skips these self-tests, because they test the harness rather than your code. Run them once after `init.sh` or `--upgrade`, or set `QS_SELFTEST=1`. CI runs them on Ubuntu and Windows with Python 3.10 and 3.12.

## Common failures

| Symptom | Meaning | What to do |
|---|---|---|
| Exit 2 before any model work | Preflight or the brief failed; the output names the problem. | Fix it and rerun. With the built-in YAML reader, check quoting, 2-space indent, and that no `cmd` contains a colon. |
| `run: BRIEF.yaml differs from the active run's brief beyond budgets` | You changed more than the budgets of an unfinished run. | Change only the budgets, or run `bash scripts/run.sh --archive` first. |
| `DONE_PARTIAL` although the agent said it was done | The controller's own check failed. | `docs/COMPLETION.json` names what failed: a criterion, the gate, the security verdict, a dirty tree, or a deadline during publishing. |
| `budget exhausted (<names>)` denials | A budget hit its limit; only the result and report could still be written. | Read "Gaps", raise the limit as described above and rerun, or take the partial work. |
| `SAFE_STOP` with `restart limit (5) reached` | The lead failed five launches in a row. | Look at `last_run.json` and `hook_log` for the repeated failure. Fix the cause, archive the run, and start again. |
| `HALT` with `active harness or brief changed` | A harness file or the brief changed during the run. | Review the change. Apply harness updates outside an active run, then start a fresh one. |
| `guard: denied (<reason>)` lines | A hook refused a hard-rule violation, a plan-tier write, a write outside a worker's files, a trifecta clash, or `cd` before `git`. | Nothing for a one-off. Repeats mean the lead is stuck, and the overseer cancels after five in a row. |
| `stall` then `replan` lines in `progress.jsonl` | The lead detected no progress and replanned. | Nothing, unless replans keep repeating. Past `replan_limit` the run ends in `SAFE_STOP`. |
| `execvpe(/bin/bash) failed` from PowerShell | `bash` resolved to the WSL stub. | Use `.\run.cmd`, or a Git Bash terminal. |
| `gate: FAIL` with `secrets: possible credential in: <file>` | The secrets scan matched a key format in a tracked or untracked file. | Remove the value and never commit it. If it was real, rotate it. |

## Sharing evidence

Share sanitized briefs and metadata from `COMPLETION.json`. Never share credentials, raw transcripts, private source or raw hook logs. Review every PR yourself before merging it. quickship never merges.
