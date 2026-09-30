# PRD: quickship — human-out-of-the-loop shipping harness

Clarifying questions were answered from the owner's stated intent ("long horizon full agentic work end to end to ship fast without human") and the approved plan; no interactive round was needed.

## Introduction

quickship is a Claude Code project harness that takes one Mission Brief and ships working software end to end with nobody answering questions during the run. A lead session plans, dispatches parallel workers into git worktrees, merges, reviews, runs a deterministic gate, and opens a pull request. The run can last hours, survive a process restart, stop itself when a budget is exhausted, and always ends with a written report. The design comes from `LONG_HORIZON_AUTONOMOUS_ORCHESTRATOR_SPEC.md` (Gulli, Arsanjani, Kashaboina, Bhagwat) applied to the existing quickship scaffold.

The problem it solves: every off-the-shelf agent loop assumes a human is reachable. Ask-the-user branches, approval queues and "stop and say so" instructions become silent stalls when nobody is there. quickship replaces each of those with a policy the agent can execute alone: choose a default and record it, skip and record it, or safe-stop with a report.

## Goals

- A human writes `BRIEF.yaml` once and reads `docs/REPORT.md` once. Nothing else is asked of them.
- Every hard rule (no force push, no push to `main`, no `.env`, no deploy config, no `pip install`, no `rm -rf`) is enforced by the repo itself, so it holds in cloud sessions and fresh clones.
- Every run terminates in exactly one of `DONE`, `DONE_PARTIAL`, `SAFE_STOP`, `HALT`, and none of them waits on a human.
- Four hard budgets (tokens, cost, wall-clock, steps) and a stall counter bound the run.
- A killed lead process resumes from on-disk ledgers without repeating side effects.
- No single step can both read untrusted web content and send data out.

## User Stories

### US-001: Gate tests the tree it runs in
**Description:** As the lead, I want `scripts/gate.sh` to check the worktree a worker ran it from, so a worker's gate result is trustworthy.

**Acceptance Criteria:**
- [ ] Root resolves from `git rev-parse --show-toplevel` before `CLAUDE_PROJECT_DIR`
- [ ] A worktree with a failing test returns exit 2 even with `CLAUDE_PROJECT_DIR` set to the main checkout
- [ ] Secrets scan covers untracked, non-ignored files
- [ ] `bash tests/run.sh` passes

### US-002: Repo-carried guardrails
**Description:** As the owner, I want the hard rules enforced by `.claude/settings.json` and a PreToolUse hook in the repo, so they apply where `~/.claude` settings do not exist.

**Acceptance Criteria:**
- [ ] `permissions.deny` lists force push, push to main/master, reset --hard, branch -D, checkout --, pip install, rm -rf, `.env*` read/write/edit
- [ ] `scripts/hooks/guard.sh` denies the same set by regex, exits 2 on malformed input, logs every call to `.claude/state/hook_log`
- [ ] Worker has no web tools; researcher has no shell; reviewer cannot write
- [ ] Worker and researcher never ask a question: ambiguity becomes an `ASSUMPTION` row in `docs/decisions.md`

### US-003: Mission Brief and ledgers
**Description:** As the owner, I want to describe a mission once in `BRIEF.yaml` with success criteria, budgets and permissions, and have the lead keep a task ledger and a progress ledger on disk.

**Acceptance Criteria:**
- [ ] `scripts/brief.py validate` writes `.claude/state/brief.json` or exits 2 naming the missing key
- [ ] `docs/ledgers/task.json` and `docs/ledgers/progress.jsonl` are written atomically by `scripts/ledger.py`
- [ ] `ledger.py stall-check` detects: unchanged state hash, same slug dispatched twice, same error signature three times, worker timeout
- [ ] `ledger.py replan` resets the stall counter and exits 3 past `replan_limit`

### US-004: Budgets and termination
**Description:** As the owner, I want the run to stop itself when any budget is exhausted and still leave a report.

**Acceptance Criteria:**
- [ ] `scripts/budget.py` reports tokens, cost, elapsed minutes, steps and which are exhausted
- [ ] On exhaustion the PreToolUse hook allows only reads and writes to `docs/REPORT.md` and `docs/RUN_STATE`
- [ ] The Stop hook refuses to end an active run without a terminal `docs/RUN_STATE`; after three refusals it writes `SAFE_STOP` itself
- [ ] `docs/RUN_STATE` is one line of JSON with `state`, `reason`, `at`

### US-005: Checkpoint, resume, idempotency
**Description:** As the owner, I want to kill the lead at any point and rerun `scripts/run.sh` without duplicated pushes or PRs.

**Acceptance Criteria:**
- [ ] `run.sh` validates the brief, resumes by session id when present, otherwise starts fresh and rebuilds from ledgers
- [ ] Restart counter with exponential backoff; `SAFE_STOP` after five restarts
- [ ] `scripts/hooks/idem.sh` denies a repeated `git push` or `gh * create` for the same step
- [ ] SessionStart on `compact` or `resume` re-injects the brief, plan status, assumptions and budget line

### US-006: Overseer
**Description:** As the owner, I want an independent process that can force a replan or cancel the run when it stagnates.

**Acceptance Criteria:**
- [ ] `scripts/overseer.sh` runs a read-only `claude -p` with write access only to `docs/overseer.md` and the two flag files
- [ ] `cancel` present: guard allows only reads and report writes
- [ ] `force_replan` present: lead deletes it and replans

### US-007: Privilege tiers and the trifecta gate
**Description:** As the owner, I want planning to be read-only and no step to both read untrusted content and send data out.

**Acceptance Criteria:**
- [ ] `.claude/state/tier` = `plan` denies source writes and non-read-only Bash
- [ ] A step that recorded an `untrusted_content` leg cannot `git push` or `gh * create`
- [ ] `ledger.py step-start` rejects a contract declaring both legs

### US-008: Contract checks and bounded critic
**Description:** As the owner, I want success criteria checked deterministically before any LLM judgement, and the critic bounded.

**Acceptance Criteria:**
- [ ] `scripts/check_criteria.py` runs `test`, `file`, `grep` kinds and defers `judge`; exit 2 on any failure
- [ ] Reviewer grades `judge` rubrics PASS/FAIL only
- [ ] Critic rounds bounded by `budgets.critic_rounds`; then `DONE_PARTIAL`

## Functional Requirements

- FR-1: The lead loop in `CLAUDE.md` must never call `AskUserQuestion` or wait on a human; the only inputs are `BRIEF.yaml` and the filesystem.
- FR-2: Ambiguity is resolved by choosing the option that best fits the goal and appending an `ASSUMPTION` row to `docs/decisions.md`.
- FR-3: An irreversible action not matched by `permissions.irreversible.allow` is skipped and recorded as `BLOCKED`; the plan routes around it.
- FR-4: A hook denial is a blocked step, never a retry of the same command.
- FR-5: Budgets are checked every turn before dispatch; exhaustion routes to synthesis with `DONE_PARTIAL`.
- FR-6: Every completed task is checkpointed to `docs/ledgers/` before the next dispatch.
- FR-7: Workers return pointers and a three-line summary, never diffs or logs.
- FR-8: `docs/REPORT.md` lists state, deliverables, criteria results, assumptions, blocked steps, uncompensated side effects, budget used, replans and stalls.
- FR-9: All hooks fail closed (exit 2) on malformed input and resolve Python via `QS_PYTHON`, `python3`, then `python`.
- FR-10: All scripts are LF-only and stdlib-only so they run unchanged on Linux cloud VMs and Git Bash.

## Non-Goals

- Connectors and OAuth beyond git and `gh`.
- Compensation of side effects beyond listing pushed branches and open PRs.
- Provider circuit breakers, model routing, cost-accurate token accounting.
- A context graph or database; long-term memory write-back; skill self-edits.
- MicroVM sandboxing beyond the cloud session sandbox.
- Overseer as a cloud routine (needs ledgers pushed to a branch; v2).
- More than one mission per repo at a time.

## Technical Considerations

- Runtime is Claude Code native: hooks, subagents, worktrees, headless `claude -p --permission-mode acceptEdits --permission-prompts none`. Never `--bare` (it skips project hooks and agents).
- `CLAUDE_PROJECT_DIR` stays at the main checkout inside a worktree; hook input `cwd` follows the worktree. State lives under `$CLAUDE_PROJECT_DIR/.claude/state`; the gate resolves its root from `$PWD`.
- PreCompact cannot inject context; SessionStart with matcher `compact|resume` can.
- Committed `.claude/settings.json` is read in single-repo cloud sessions; `~/.claude/settings.json` is not.
- Windows: `core.longpaths true`, slugs capped at 24 characters, Python emits CRLF so hooks strip `\r`.

## Success Metrics

- A brief for a small feature runs to `DONE` with a PR and report, unattended, on the first try.
- `kill -9` mid-run followed by `run.sh` resumes and creates no duplicate PR.
- A `steps: 5` brief ends in `DONE_PARTIAL` with the gap listed.
- `bash tests/run.sh` covers every hook and script without an LLM call and passes on Git Bash and Linux.

## Open Questions

- Token accounting from transcripts is approximate; steps and wall-clock are the exact stops. Revisit once a run's `total_cost_usd` can be compared to the estimate.
- Whether the overseer should run as a cloud routine once ledgers are pushed to the session branch (v2).
