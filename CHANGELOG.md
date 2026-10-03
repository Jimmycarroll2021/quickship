# Changelog

All notable changes to quickship are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The current version is in `VERSION`.

## [0.1.0] - 2026-10-03

First public release: a Claude Code harness that takes one Mission Brief and ships a pull request with nobody answering questions during the run.

### Added

- **Safe scaffold and hooks.** `.claude/settings.json` deny rules and `scripts/hooks/guard.sh` enforce the hard rules (no PR merges, no push to `main`, no force push or history rewrite, no `.env` or deploy config, no `rm -rf` or `pip install`) inside the repo, so they hold in cloud sessions and fresh clones. `scripts/gate.sh` detects the stack, runs lint, tests and build, scans tracked and untracked files for secrets, and tests the worktree it is run from. Planner, worker, researcher and reviewer subagents, with the worker cut off from the web and the researcher cut off from the shell.
- **Brief, ledgers, budgets, termination.** `BRIEF.yaml` validated by `scripts/brief.py` (PyYAML or a strict built-in reader). A task ledger and an append-only progress ledger under `docs/ledgers/`, written atomically by `scripts/ledger.py`, with stall detection and bounded replans. Four hard budgets (tokens, cost, wall-clock, steps) read from the transcript by `scripts/budget.py`; once one is exhausted the hook allows only the report. Every run ends in `DONE`, `DONE_PARTIAL`, `SAFE_STOP` or `HALT` in `docs/RUN_STATE`, and the Stop hook refuses to end an active run without one.
- **Resume, idempotency, overseer.** `scripts/run.sh` launches the lead headlessly, resumes it by session id after a kill, backs off on restarts and gives up after five. `scripts/hooks/idem.sh` denies a repeated push or PR creation for the same step. SessionStart re-injects the brief, plan and budget after a compaction or resume. An overseer process runs beside the lead with write access only to `docs/overseer.md` and the `cancel` and `force_replan` flags. A finished run's artifacts are archived to `docs/runs/` when the next mission starts.
- **Tiers, trifecta, criteria, critic.** A read-only plan tier for the planner. No step may both read untrusted content and push or open a PR. `scripts/check_criteria.py` runs `test`, `file` and `grep` criteria deterministically and defers `judge` rubrics to the reviewer, which grades PASS or FAIL in a bounded number of critic rounds.
- **Release.** `scripts/init.sh` installs the harness into any project from `scripts/manifest.txt`, seeds `BRIEF.yaml` and `docs/decisions.md`, records `.quickship/VERSION`, and refreshes unmodified files with `--upgrade`. `run.cmd` and `init.cmd` wrappers for Windows that locate Git Bash. The reviewer may run the brief's test commands and the project's eval to grade a `judge` criterion. The token budget excludes cache reads (`cache_read_tokens` and `tokens_total` reported separately). PR creation through the MCP GitHub tool is covered by the idempotency hook. `scripts/overseer_status.py` gives the overseer one summary of ledgers, budget and flags. CI runs the self-tests on Ubuntu and Windows. In an installed copy the gate skips the harness self-tests (`QS_SELFTEST=1` forces them), so a merge's gate takes seconds, not minutes. `budget.py` reports `near` at 85% of a limit so the lead wraps up with a PR before the budget hook cuts it off. Worker, reviewer and lead prompts carry the shell discipline that keeps headless commands inside the allow list. README, runbook, example briefs, licence and this changelog.

### Verified

Seven unattended missions ran with this release:

- README mission on quickship itself: `DONE` in 37 minutes, 72 steps, about $4.56, PR opened.
- Same goal with `steps: 12`: `DONE_PARTIAL` in about 5 minutes, $1.68, report written with the gap listed.
- Kill and resume: the lead killed mid-task, `run.sh` resumed the same session, `DONE`, exactly one push and one PR in `idem.jsonl`, $1.59.
- `claude --cloud` run: `DONE`, 26 steps, about $1.24, PR opened through the GitHub tool on the session's `claude/*` branch.
- localrag, a CPU-only private RAG assistant over three PDFs (llama.cpp, GGUF, sqlite): `DONE` in 96 minutes, 257 steps, about $3.40, 4 tasks including one the lead added after a weak eval, PR with 2,134 lines added.
- A docs mission in a project installed by `init.sh`, before the last fixes: the deliverable merged but the run hit its 30-minute limit after the worker and critic lost about 10 minutes to permission denials. `DONE_PARTIAL`, no PR.
- The same kind of mission after them: `DONE` in 7.7 minutes, 63 steps, about $0.95, all three criteria PASS, the judge graded on output the critic produced itself, PR opened on GitHub.

[0.1.0]: https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.1.0
