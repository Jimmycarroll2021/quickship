# Changelog

All notable changes to quickship are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The current version is in `VERSION`.

## [0.3.1] - Unreleased

### Added

- `QS_TEST_LOG_DIR` retains separate per-suite output, exit codes and job counts for local acceptance evidence.

- `mission.requirements`: an optional list of stable `REQ-xxx` identifiers from `docs/PRD.md`. `brief.py`
  validates it, the strategist writes it into every mission, and the controller renders it into the PR's
  Traceability section instead of the "not declared" placeholder.
- `docs/PRD_TEMPLATE.md`, installed with the harness, gives the strategist's PRD a fixed shape with
  per-requirement acceptance criteria and a mission-to-requirement table.
- The controller renders the PR body from `.github/pull_request_template.md` with the mission branch,
  final commit, reviewable diff size and the lead's report (shipped on main after 0.3.0).
- Agent shell commands run inside Claude Code's OS sandbox where the platform supports it: `.claude/settings.json`
  enables it with no unsandboxed retry and a network allowlist of GitHub and the npm and PyPI registries.
  `preflight.py` reports `sandbox.available` and why not on native Windows or without `bubblewrap`/`socat`.
- Controller runs allowlist the shell: an executable runs only if it is in the base set or named by a brief
  `quality` command or `test` criterion. Leading `NAME=value` assignments no longer hide a command from the rules.
- Preflight refuses a `quality.profile: docs` brief that has neither `mission.base` nor a resolvable
  `origin/HEAD`, instead of the gate failing after the model has run.

### Fixed

- Operator cancellation is rechecked during final verification and before publication commands. It records non-retryable SAFE_STOP and preserves receipts for completed publication side effects.
- Documentation-only quality checks require a resolvable mission base or `origin/HEAD`; a missing base no longer turns an empty working-tree diff into a pass.
- Installed-copy tests inherit the outer job limit. Windows defaults to one job, other platforms to at most four; invalid overrides fail before dispatch.
- Standalone harness self-tests have a 90-minute limit for serial installed-copy coverage. Ordinary project checks retain 15 minutes, and mission deadlines remain authoritative.
- The self-tests clear an inherited `CLAUDE_PROJECT_DIR`. The Stop hook's gate runs the suite with that
  variable set, which pointed every fixture at the real repo's `.claude/state` and failed the gate on every
  stop in this repo while CI stayed green.
- `scripts/init.sh` names the "PR sizing and evidence" section among those to merge into an existing CLAUDE.md.
- `scripts/init.sh` adds `__pycache__/` to the project's `.gitignore`. The harness's own Python imports wrote
  bytecode under `scripts/__pycache__/` as untracked files, which failed the docs profile and the controller's
  clean-tree check in any project without a global ignore for it.
- The README's Quickstart commits every file `init.sh` installs; it had left the PR and PRD templates untracked,
  which preflight refuses.

## [0.3.0] - 2026-10-03

### Changed

- Publishing and authoritative completion moved to a separate Python supervisor. Exit 0 requires
  independent gate, criteria, deliverable, final-commit security and GitHub branch/PR verification.
- Quality checks no longer silently pass when missing. Briefs support explicit commands, skip reasons
  and a documentation-only profile that rejects application-code changes.
- Safeguards are documented as cooperative controls, not an OS sandbox. Subscription cost values
  are API-equivalent estimates. Supported platforms are Ubuntu/Windows Git Bash, Python 3.10+,
  Claude Code >=2.1.288. Cloud/macOS execution remain unverified.
- Exit codes: 0 DONE, 2 invalid setup/brief, 3 partial/safe stop, 4 HALT, 5 controller failure.

### Fixed

- PR-merge/protected-ref/deployment-write policy gaps; agents no longer have publishing authority.
- Full incremental transcript accounting, serialized counters/ledgers and per-agent step bindings.
- Controller deadlines terminate owned process trees and preserve interruption/resume evidence.
- Upgrade checksums reflect actual target files; skipped modifications preserve the installed version
  and block preflight until conflicts are resolved.
- Review fixes before release:
  - A lead that crashed before writing its ledgers no longer loses the run: `archive-stale` also
    recognises the goal frozen in `controller.json`, so the next launch resumes instead of archiving.
  - `program.sh` no longer reads a predecessor's `DONE` as the current mission's when `run.sh` fails
    early. `DONE` also requires exit 0; otherwise the chain records `FAILED rc=<n>` and stops.
  - `program.sh` retries only outcomes the controller marks `retryable` in `COMPLETION.json`
    (a crashed lead or an interrupted controller).
  - `bash scripts/run.sh --archive` archives a finished run so a changed brief can start fresh; it
    refuses an unfinished one. A change to the `budgets` block alone continues the same run.
  - Child output is read as UTF-8 with replacement, so undecodable stderr can't block the lead.
  - Hooks fail closed: the budget hook denies on any error, the gate exits only 0 or 2, and the
    SubagentStop evidence hook never blocks the same subagent twice.
  - An unquoted newline is a command separator for the guard in every mode.
  - The researcher has no shell again.
  - `git push -uf` (and any short-flag cluster containing `f`) is caught as a force push.
  - The guard decides whether a controller run is active the same way the controller does, so an
    empty `controller.json` can no longer switch off the trifecta check.
  - `docs/RELEASE-EVIDENCE.md` no longer contains local paths, private repository names or session ids.

### Validation

See docs/RELEASE-EVIDENCE.md for verified results and remaining release gates.

## [0.2.0] - 2026-10-03

### Added

- **Idea to missions.** `scripts/idea.sh` runs a strategist agent once over `IDEA.md`. It writes `docs/PRD.md`, covering the user, the pain, the riskiest assumptions and the MVP scope, plus two to five sequenced mission briefs with testable criteria. `brief.py check` validates them without touching run state.
- **Mission chains.** `scripts/program.sh` runs the mission briefs in order. Each mission starts from the previous mission's branch and opens its PR against it through the new `mission.base` brief field, so you get a stack of PRs to review and merge. The chain stops at the first mission that isn't `DONE`, and resumes by skipping finished ones. `diffbase.sh` honours `mission.base`, so reviews see only the current mission.
- **QA.** A read-only `security` reviewer runs on every mission's diff, and its high and medium findings become tasks. Workers must ship a test with every behaviour change, and the reviewer fails code changes that have none. UI missions written by the strategist carry a Playwright criterion.
- **Windows wrappers:** `idea.cmd` and `program.cmd`. New template: `IDEA.example.md`.

### Verified

- From idea to MVP, unattended. A one-paragraph idea, an offline CLI that summarises GPX bike rides by ISO week, became a PRD and four mission briefs in 93 seconds. The four missions then ran back to back, and all ended `DONE` in 41 minutes. The result is a stack of four PRs adding 1,618 lines, with 46 passing tests, clean lint and a working CLI. On the third mission the security reviewer raised a finding, and the lead fixed it before opening the PR. Across all sessions the run made 563 tool calls and used 1.22M uncached tokens plus 14.5M cache reads.

## [0.1.1] - 2026-10-03

### Fixed

- **Budgets count subagent spend.** Current Claude Code writes each subagent's transcript to `<session>/subagents/`, which `budget.py` did not read. The token and cost budgets therefore missed every worker, planner and reviewer call, and the cost cap tripped late. Recomputed from the full transcripts, the v0.1.0 missions used two to four times what their reports showed.
- **Unknown models are priced conservatively.** A model missing from the rate table, such as a newer release, was priced as Sonnet. It is now priced at the highest known rate, so the cost cap errs high.
- **Stale contract line.** `CLAUDE.md`, which is installed into every project, no longer says the repo has no application stack.

### Changed

- **New README** with a banner, diagrams of the architecture, a run sequence, the guardrail layers and the terminal states, a track record recomputed from transcripts, and a section on when quickship fits. Also new: `CONTRIBUTING.md`.
- **Example briefs** have higher `cost_usd` limits to match the corrected accounting.

## [0.1.0] - 2026-10-03

First public release: a Claude Code harness that takes one Mission Brief and ships a pull request with nobody answering questions during the run.

### Added

- **Safe scaffold and hooks.** `.claude/settings.json` deny rules and `scripts/hooks/guard.sh` enforce the hard rules (no PR merges, no push to `main`, no force push or history rewrite, no `.env` or deploy config, no `rm -rf` or `pip install`) inside the repo, so they hold in cloud sessions and fresh clones. `scripts/gate.sh` detects the stack, runs lint, tests and build, scans tracked and untracked files for secrets, and tests the worktree it is run from. Planner, worker, researcher and reviewer subagents, with the worker cut off from the web and the researcher cut off from the shell.
- **Brief, ledgers, budgets, termination.** `BRIEF.yaml` validated by `scripts/brief.py` (PyYAML or a strict built-in reader). A task ledger and an append-only progress ledger under `docs/ledgers/`, written atomically by `scripts/ledger.py`, with stall detection and bounded replans. Four hard budgets (tokens, cost, wall-clock, steps) read from the transcript by `scripts/budget.py`; once one is exhausted the hook allows only the report. Every run ends in `DONE`, `DONE_PARTIAL`, `SAFE_STOP` or `HALT` in `docs/RUN_STATE`, and the Stop hook refuses to end an active run without one.
- **Resume, idempotency, overseer.** `scripts/run.sh` launches the lead headlessly, resumes it by session id after a kill, backs off on restarts and gives up after five. `scripts/hooks/idem.sh` denies a repeated push or PR creation for the same step. SessionStart re-injects the brief, plan and budget after a compaction or resume. An overseer process runs beside the lead with write access only to `docs/overseer.md` and the `cancel` and `force_replan` flags. A finished run's artifacts are archived to `docs/runs/` when the next mission starts.
- **Tiers, trifecta, criteria, critic.** A read-only plan tier for the planner. No step may both read untrusted content and push or open a PR. `scripts/check_criteria.py` runs `test`, `file` and `grep` criteria deterministically and defers `judge` rubrics to the reviewer, which grades PASS or FAIL in a bounded number of critic rounds.
- **Release.** `scripts/init.sh` installs the harness into any project from `scripts/manifest.txt`, seeds `BRIEF.yaml` and `docs/decisions.md`, records `.quickship/VERSION`, and refreshes unmodified files with `--upgrade`. `run.cmd` and `init.cmd` wrappers for Windows that locate Git Bash. The reviewer may run the brief's test commands and the project's eval to grade a `judge` criterion. The token budget excludes cache reads (`cache_read_tokens` and `tokens_total` reported separately). PR creation through the MCP GitHub tool is covered by the idempotency hook. `scripts/overseer_status.py` gives the overseer one summary of ledgers, budget and flags. CI runs the self-tests on Ubuntu and Windows. In an installed copy the gate skips the harness self-tests (`QS_SELFTEST=1` forces them), so a merge's gate takes seconds, not minutes. `budget.py` reports `near` at 85% of a limit so the lead wraps up with a PR before the budget hook cuts it off. Worker, reviewer and lead prompts carry the shell discipline that keeps headless commands inside the allow list. README, runbook, example briefs, licence and this changelog.

### Verified

Seven unattended missions ran with this release, including a real application and a kill-and-resume run. The figures, recomputed in 0.1.1 from the full transcripts, are in the README under "Track record".

[0.3.0]: https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.3.0
[0.2.0]: https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.2.0
[0.1.1]: https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.1.1
[0.1.0]: https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.1.0
