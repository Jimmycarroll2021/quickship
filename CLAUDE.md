# quickship — agent instruction contract

## What this is
quickship is a Claude Code harness for unattended software delivery: a lead session plans, dispatches parallel workers into git worktrees, merges, reviews, gates, and opens a PR, with no human answering questions during the run. The repo carries its own guardrails (`.claude/settings.json` deny rules plus `scripts/hooks/guard.sh`) so the hard rules hold in cloud sessions and fresh clones where `~/.claude` settings do not exist. Requirements are in `tasks/prd-quickship.md`.

## Commands
`scripts/gate.sh` is the single source of truth. It detects the stack from the repo root at run time:

| Detected by | Install | Lint | Test | Build |
|---|---|---|---|---|
| `package.json` + `pnpm-lock.yaml` / `yarn.lock` / `bun.lock*` / (none → npm) | `<pm> install` | `<pm> run lint` | `<pm> run test` | `<pm> run build` |
| `pyproject.toml` or `requirements.txt` (`uv run` prefix if `uv.lock`) | `uv sync` / `pip install -r requirements.txt` | `ruff check .` | `pytest -q` | `uv build` / `python -m build` (only if `[build-system]` present) |

Run everything with:

```bash
bash scripts/gate.sh   # exit 0 = pass, 2 = fail (details on stderr)
```

The gate also runs `bash tests/run.sh`, the repo's own acceptance tests for its hooks and scripts (no LLM calls), in the quickship repo itself; an installed copy (`.quickship/VERSION` present) skips them unless `QS_SELFTEST=1`, because they take minutes and test the harness rather than the project. Headless note: in a `claude -p` run on a folder that was never trusted interactively, Claude Code ignores the `permissions.allow` rules in `.claude/settings.json` (hooks and `deny` rules still apply), so a headless launcher must pass the allow list with `--allowedTools`. Cloud sessions (`claude --cloud`) clone the pushed branch, so `BRIEF.yaml` must be committed; they assign their own `claude/*` branch, which then serves as the session branch; they have no `gh`, so the lead opens the PR with the GitHub tool, which the idempotency hook also covers. No application stack exists yet, so lint/test/build are skipped with a warning until a manifest is added. The gate resolves its root from the tree it is run in, so a worker must run it from inside its worktree.

## Definition of done
A change is done only when all of these hold:
1. Lint clean.
2. Tests green.
3. Build passes.
4. No secrets committed (no API keys, tokens, private keys or `.env` values in tracked files).

`bash scripts/gate.sh` exiting 0 checks 1–4. A Stop hook runs it automatically.

## Hard rules
- Never merge PRs.
- Never force-push (`--force`, `--force-with-lease`, `+refspec`), rebase shared branches or rewrite published history.
- Never touch production config: `.env*` (other than `*.example`), deployment/infra config (e.g. `vercel.json`, `fly.toml`, `netlify.toml`, `Dockerfile*` used for deploy, `infra/`, `terraform/`, `k8s/`, `.github/workflows/*deploy*`), or hosting/dashboard settings via connectors.
- Never push to `main`. Work on a feature branch.
- When the work is done and the gate passes: open a PR and stop. Do not self-review or merge it; hand it back.

These rules are enforced, not just stated: `.claude/settings.json` denies the matching tool calls, and `scripts/hooks/guard.sh` (PreToolUse; runs inside subagents too) denies them again by regex and logs every call to `.claude/state/hook_log`. A denied call is a blocked step: record it in `docs/decisions.md` and route around it. Never retry the same command.

## Subagents
- `planner` (`.claude/agents/planner.md`): turns a goal into a file-disjoint task list in `docs/plan.md`.
- `worker` (`.claude/agents/worker.md`): implements one bounded task and returns a summary and file paths. No web tools.
- `researcher` (`.claude/agents/researcher.md`): answers one question from the web, writes only under `work/_untrusted/`. No shell, cannot push.
- `reviewer` (`.claude/agents/reviewer.md`): read-only audit against the definition of done; returns PASS or a numbered FAIL list.

A worker never fetches the web and a researcher never runs commands or pushes, so no single step can both read untrusted content and send data out (the lethal-trifecta rule). If a worker returns `NEEDS-RESEARCH`, dispatch a researcher as a separate step, then re-dispatch the worker with the file path.

## Running a mission
The human installs the harness into a project once with `bash scripts/init.sh <project-dir>` (`init.cmd` from PowerShell; `--upgrade` later refreshes unmodified harness files), writes `BRIEF.yaml` (see `BRIEF.example.yaml`: goal, deliverables, success criteria, budgets, permissions), commits it, and runs `bash scripts/run.sh` (`run.cmd` from PowerShell, where plain `bash` is the WSL stub). That validates the brief, starts or resumes the lead session headlessly with the allow list passed via `--allowedTools`, and runs the overseer beside it. The human reads `docs/REPORT.md` when `docs/RUN_STATE` becomes terminal. Nothing else is asked of them. Contracts for every file and hook are in `docs/design/contracts.md`.

## Lead loop
You never ask a question. Nobody is reading. Every choice is one of: choose the default and record it, skip and record it, or safe-stop with a report. `python3` below means `python` where `python3` is missing.

0. **Anchor.** Read `.claude/state/brief.json` (written by `python3 scripts/brief.py validate`). Its goal, success criteria and permissions govern every step and are re-read every turn.
1. **Resume.** First `python3 scripts/ledger.py archive-stale`: a terminal `docs/RUN_STATE` whose ledgers carry a different goal than the brief belongs to an earlier, merged mission and is moved to `docs/runs/`. Then, if `docs/RUN_STATE` is terminal, stop. Be on the session branch `mission/<goal-slug>` (kebab-case, max 24 chars): create it from the current HEAD if absent, check it out if it exists. If `docs/ledgers/task.json` exists, load it: `merged` tasks are done; for `dispatched` tasks check `git worktree list` and `git branch --list` and reuse what exists. Otherwise `python3 scripts/ledger.py init --goal "<goal>"` and `python3 scripts/ledger.py tier plan`. Never write `.claude/state/` files with a shell redirect; Claude Code protects that path and the write is denied.
2. **Plan.** Run `planner`. It writes `docs/plan.md` and registers tasks in the ledger. On a replan, tell it the stall or failure reason; it must invalidate disproved facts and change the approach. Then `python3 scripts/ledger.py tier act` as its own command: the guard checks the tier before the line runs, so an act-tier command chained onto it with `&&` is denied.
3. **Check, every turn before dispatch.** `python3 scripts/budget.py`: any dimension exhausted → step 8 as `DONE_PARTIAL`. Any dimension in `near` (85% of its limit) → finish the task in flight, dispatch nothing new, step 8 as `DONE_PARTIAL` if work remains: once a limit is exhausted the budget hook refuses commands, the push and PR included. `steps` counts every tool call in the run, the subagents' included, so spend them on the work, not on re-reading state. `.claude/state/cancel` exists → step 8 as `SAFE_STOP`. `.claude/state/force_replan` exists → delete it, `python3 scripts/ledger.py replan` (exit 3 → step 8 as `SAFE_STOP`), step 2.
4. **Dispatch.** Take the next `pending` task. `python3 scripts/ledger.py step-start <slug> --legs <untrusted_content|outbound|none>` (a task that needs the web gets a `researcher` step first, never both legs in one step). `task-set <slug> dispatched`, `append dispatched <slug> "<goal>"`. Create the worktree only if absent: `git worktree add .claude/worktrees/<slug> -b <session-branch>--<slug>`. Dispatch one `worker` (or `researcher`), told its worktree path and owned files, with a 20-minute limit; a timeout is `append timeout <slug> "worker timeout"`. Workers commit with `git -C <worktree> add <files> && git -C <worktree> commit ...`. Never `cd <dir> && git ...`: Claude Code treats a `cd` before any git command as needing approval, which a headless run cannot give, so the guard denies it up front and says so. `cd <worktree> && bash scripts/gate.sh` is fine. One command per Bash call beyond that: Claude Code's permission layer refuses what it cannot match to an allow rule, and the relative rules (`bash tests/x.sh`) never match an absolute script path, a redirect into `/tmp`, or `${PIPESTATUS[0]}`; the tool reports the exit code itself. A refused compound command says nothing about its bare form: try that before recording a block. Independent tasks may run in parallel, one step id each.
5. **Integrate.** `git merge --no-ff <session-branch>--<slug>`, run `reviewer`, run `bash scripts/gate.sh`. Success: `task-set <slug> merged --commit <sha>`, `append merged <slug> "<summary>"`, one row in `docs/decisions.md`. Failure: `append failed <slug> "<first line of the error>"`, re-dispatch with the error in context, at most 3 times, then `task-set <slug> failed`.
6. **Stall check, after every task.** `python3 scripts/ledger.py stall-check`. Exit 1 means a stall was counted; when `stall_count` exceeds `budgets.stall_limit`, `python3 scripts/ledger.py replan` (exit 3 → step 8 as `SAFE_STOP`) and go to step 2.
7. **Ambiguity and irreversibles.** An underdetermined choice: pick the option that best fits the goal, `append assumption <slug> "<choice>"`, continue. An irreversible action not matched by `permissions.irreversible.allow` in the brief: do not run it, `append blocked <slug> "<action>"`, route around it. A hook denial is a blocked step, never a reason to retry the same command.
8. **Synthesis**, when no task is `pending` or a terminal condition fired: `python3 scripts/check_criteria.py`. Failing criteria with budget left become new tasks (steps 4 to 6), at most `budgets.critic_rounds` times. Then `reviewer` as critic: it grades any `judge` criterion PASS or FAIL on evidence it produced itself (the guard lets it run the brief's `test` commands, `check_criteria.py` and the project's test or eval runners); a FAIL without quoted command output is not a grade, re-run it once. Give it the brief's `test` commands exactly as the brief writes them, never wrapped or with extra arguments: the guard matches them verbatim. A quoted result whose command has a DENY line in `.claude/state/hook_log` is not evidence. Record each grade: `python3 scripts/check_criteria.py --judge <index> PASS|FAIL --evidence "<the quoted output>"` (index = the criterion's position in the brief, 0-based), so `criteria.json` carries the verdict and its evidence. Then the gate. Then push the session branch and `gh pr create` (both idempotent; a repeat is denied and the recorded result stands). The PR title gets `[partial]` for `DONE_PARTIAL`.
9. **Terminate.** Write `docs/REPORT.md`: state, deliverables and PR URL, criteria table, assumptions, blocked steps, uncompensated side effects (pushed branches, open PR), budget used per dimension, replans with reasons, stalls, overseer notes, gaps. Then write `docs/RUN_STATE` as one line: `{"state":"DONE|DONE_PARTIAL|SAFE_STOP|HALT","reason":"...","at":"<iso utc>"}`. `HALT` is only for a policy violation (a secret committed, a sandbox breach) and skips synthesis. Then stop. The Stop hook refuses to end an active run without a terminal `docs/RUN_STATE`.
10. **Clean up** after each merge: `git worktree remove .claude/worktrees/<slug>` and `git branch -d <session-branch>--<slug>`. Never push task branches.

`.claude/worktrees/`, `.claude/state/` and `work/_untrusted/` are gitignored. Never `git add` them.
