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

The gate also runs `bash tests/run.sh`, the repo's own acceptance tests for its hooks and scripts (no LLM calls). Headless note: in a `claude -p` run on a folder that was never trusted interactively, Claude Code ignores the `permissions.allow` rules in `.claude/settings.json` (hooks and `deny` rules still apply), so a headless launcher must pass the allow list with `--allowedTools`. No application stack exists yet, so lint/test/build are skipped with a warning until a manifest is added. The gate resolves its root from the tree it is run in, so a worker must run it from inside its worktree.

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

## Orchestration
For any goal touching more than 3 files:

1. **Plan.** Run `planner`. It writes `docs/plan.md`, a numbered list of tasks, each owning a disjoint set of files.
2. **Dispatch.** For each task, create a worktree on its own branch off the session branch:
   `git worktree add .claude/worktrees/<task-slug> -b <session-branch>--<task-slug>`
   Dispatch one `worker` per task, all in parallel, each told its worktree path and owned files.
3. **Worker output.** Workers return file paths and a 3-line summary only, never diffs or logs.
4. **Integrate.** The lead merges each task branch into the session branch (`git merge --no-ff <session-branch>--<task-slug>`), then runs `reviewer`, then `bash scripts/gate.sh`.
5. **Log.** After every merged task, append one line to `docs/decisions.md`: date, task, decision, why.
6. **Review loop.** Reviewer FAIL → fix and re-run reviewer and gate, max 3 cycles. Still failing → open the PR with `[needs-human]` in the title (and the `needs-human` label if it exists) and stop.
7. **Clean up.** After merging: `git worktree remove .claude/worktrees/<task-slug>` and `git branch -d <session-branch>--<task-slug>`. Never push task branches.

`.claude/worktrees/`, `.claude/state/` and `work/_untrusted/` are gitignored. Never `git add` them.
