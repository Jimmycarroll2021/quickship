# quickship

quickship is a Claude Code harness for unattended software delivery. You write a short mission brief, run one command, and walk away. A lead Claude session plans the work, dispatches parallel workers into git worktrees, merges their branches, reviews, runs the quality gate, and opens a pull request. Nobody answers questions during the run: every ambiguous choice is resolved with a default and written down for you to read afterwards.

You end up with a PR to review and a report explaining what happened. You still merge the PR yourself.

## Prerequisites

- `git`, with the repo cloned and a clean-enough working tree.
- Python 3.10+ (the scripts use only the standard library; PyYAML is used if installed).
- The `claude` CLI, installed and logged in. `scripts/run.sh` calls `claude -p`.
- `gh` (GitHub CLI), authenticated (`gh auth status`), for the final PR step.
- A bash shell (Git Bash on Windows).

## 1. Write BRIEF.yaml

Copy the example to the repo root and edit it:

```bash
cp BRIEF.example.yaml BRIEF.yaml
```

Fields (all required unless marked otherwise):

| Field | Meaning |
|---|---|
| `mission.goal` | One or two sentences: what to build or change. |
| `mission.deliverables` | List of files or outputs the mission must produce (non-empty). |
| `success_criteria` | Non-empty list of checks that decide "done". Each has a `kind`, see below. |
| `budgets` | Limits that stop the run: `tokens`, `cost_usd`, `wall_clock_min`, `steps` (all numbers > 0). Optional counts: `stall_limit` (default 3), `replan_limit` (5), `critic_rounds` (2). |
| `permissions.irreversible.default` | `skip-and-record` (do not run the action, log it as blocked) or `allow`. |
| `permissions.irreversible.allow` | Optional list of command patterns permitted even under `skip-and-record`. |
| `ambiguity_policy` | Must be `choose-default-and-record`: pick a sensible default and log it as an assumption. |

Success criteria kinds:

| Kind | Fields | Passes when |
|---|---|---|
| `test` | `cmd`, `expect` (exit code, default 0) | the command exits with the expected code |
| `file` | `path`, optional `must_contain` | the file exists (and contains the string) |
| `grep` | `pattern`, `path` | the pattern matches in the file |
| `judge` | `rubric` | the reviewer agent grades the rubric PASS |

Worked example (this is `BRIEF.example.yaml`):

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

YAML notes: use 2-space indentation; each success criterion is a single-line `{key: value}` map. Without PyYAML, a strict built-in reader handles the subset above (no anchors, multi-line scalars or nested flow maps).

If the brief is invalid, `run.sh` exits 2 and prints one line naming the bad key, for example `brief: missing mission.goal` or `brief: unknown kind 'x' (want one of ('test', 'file', 'grep', 'judge'))`. Check a brief without starting anything:

```bash
python scripts/brief.py validate
```

## 2. Run it

```bash
bash scripts/run.sh
```

That is the only command. It validates the brief, starts the lead headlessly with the repo's allow list, and runs the overseer beside it.

Optional environment variables:

| Variable | Effect |
|---|---|
| `QS_OVERSEER=0` | Do not run the overseer. |
| `QS_OVERSEER_MIN` | Overseer interval in minutes (default 15). |
| `QS_PYTHON` | Python interpreter to use (default: `python3`, else `python`). |

Example: `QS_OVERSEER_MIN=5 bash scripts/run.sh`.

## 3. What happens while it runs

1. The lead reads the validated brief and creates a session branch `mission/<goal-slug>`.
2. A planner splits the goal into file-disjoint tasks in `docs/plan.md`.
3. Each task goes to a worker in its own git worktree under `.claude/worktrees/`, on its own branch. Independent tasks run in parallel.
4. The lead merges each task branch into the session branch, has a reviewer audit it, and runs `bash scripts/gate.sh`.
5. Stalls and failures trigger retries or a replan, within the budgets in your brief.
6. At the end the lead checks your success criteria, runs the gate, pushes the session branch, opens a PR with `gh`, and writes the report.

The overseer is a watchdog that checks progress every few minutes and writes notes to `docs/overseer.md`. Workers never touch the web; a separate researcher agent does that, so no single step both reads untrusted content and sends data out.

## 4. How to know it finished

`docs/RUN_STATE` appears as one line of JSON. `run.sh` also prints `run: lead exit=... state=...` when it returns.

| State | Meaning |
|---|---|
| `DONE` | Criteria met, gate passed, PR opened. |
| `DONE_PARTIAL` | A budget ran out first. The PR title is tagged `[partial]`. |
| `SAFE_STOP` | Cancelled, replan limit hit, or restart limit (5) reached. |
| `HALT` | Policy violation such as a committed secret. Synthesis is skipped. |

## 5. Where to read results

| File | Contents |
|---|---|
| `docs/REPORT.md` | Start here: state, deliverables and PR URL, criteria table, assumptions, blocked steps, side effects, budget used, replans, stalls, gaps. |
| `docs/decisions.md` | One row per merge, assumption or blocked step. |
| `docs/ledgers/` | Machine-readable task ledger and event log. |
| `docs/overseer.md` | Watchdog notes. |
| `docs/plan.md` | The task plan. |

Review the PR, then merge it yourself.

## Resume or restart

If the run stopped without a terminal state (crash, closed terminal), run the same command again. It resumes the lead through the saved session id and the ledgers:

```bash
bash scripts/run.sh
```

If `docs/RUN_STATE` is already terminal, `run.sh` just prints it and exits. To start a completely fresh mission, remove the run's state first. Only do this when you are sure you no longer need the old report:

```bash
rm docs/RUN_STATE && rm -r docs/ledgers .claude/state
```

Then edit `BRIEF.yaml` if needed and run `bash scripts/run.sh` again.

## What it will not do

These are enforced by `.claude/settings.json` deny rules and the `scripts/hooks/guard.sh` hook, not just requested:

- Never merges PRs.
- Never pushes to `main`; work stays on `mission/*` branches.
- Never force-pushes or rewrites published history.
- Never touches `.env*` (except `*.example`), deployment or infra config, or hosting settings.
- Never commits secrets.

A denied action is recorded as a blocked step in `docs/decisions.md` and routed around, never retried.

## Definition of done

A change is done when this exits 0 (lint, tests, build, no secrets; it also runs `tests/run.sh`):

```bash
bash scripts/gate.sh
```

## Deeper reading

- `CLAUDE.md`: the agent contract, hard rules and the full lead loop.
- `docs/design/contracts.md`: contracts for every file, script and hook.
- `BRIEF.example.yaml`: the annotated example brief.
