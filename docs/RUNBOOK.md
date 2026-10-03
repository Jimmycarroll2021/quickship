# Quickship v0.3 runbook

## Before a mission

Install/upgrade in a trusted development project, resolve .quickship/conflicts, edit and commit
BRIEF.yaml, then run `python scripts/preflight.py`. This checks versions/authentication/quality
configuration without model calls. Claude Code >=2.1.288, Git, Python 3.10+, gh and bash 4+ are required.
On Windows use Git Bash or the .cmd wrappers. Never install into sensitive originals or live production.
For subscription-only work verify paid extra usage is disabled; Quickship never changes billing.

## Run and observe

Run `bash scripts/run.sh` or `.\run.cmd`. Read docs/ledgers/progress.jsonl and use
`python scripts/budget.py` / `python scripts/overseer_status.py`. The lead and watchdog are
children owned by the supervisor. Local logs may contain private project information.

The controller alone publishes. An agent submits RESULT.json (READY, DONE_PARTIAL, SAFE_STOP or HALT).
The controller independently checks gate, criteria, deliverables, security on the final commit and
GitHub branch/PR, then writes RUN_STATE, COMPLETION.json and an authoritative report heading.

Exit 0 means verified DONE; 2 means preflight/brief failure; 3 means incomplete/safe stop;
4 means policy HALT; 5 means controller failure. Read REPORT.md and COMPLETION.json before judging success.
DONE_PARTIAL does not promise a PR. Check the recorded uncompensated side effects after a publishing error.

## Interrupt, cancel, resume

Ctrl+C preserves the session and ledgers and writes SAFE_STOP. Create .claude/state/cancel to request
cancellation. The supervisor terminates its owned process tree, including the watchdog, on cancellation
or deadline. Remove your own cancel flag before resuming. Run the same command; the original deadline
and usage remain. Five launches are allowed. DONE is never republished; HALT requires review.

Do not edit active BRIEF.yaml or harness files. Stop and preserve/archive the run before changing policy.
Old v0.2 active state is incompatible: keep its report/session/ledgers and archive the runtime directory
and run artifacts yourself. No automatic migration deletes them. A new mission goal archives the prior
finished run under docs/runs and starts fresh runtime accounting.

## Quality and skips

Required checks fail if missing. Configure quality.lint/test/build as commands or explicit operator
skip reasons. Docs profile is explicitly selected and rejects application-code changes. Python builds
are automatically not applicable only when no build system is declared. The project's test/dependency
commands remain trusted code with the operator's access.

## Upgrade

Use init.sh --upgrade only when no mission is active. Modified files/custom instructions are preserved.
Read .quickship/conflicts; reconcile each listed file against the new harness and rerun installation.
An incomplete upgrade cannot pass preflight or claim the new version. Review the v0.3 CLI exit changes,
quality requirements and controller-owned publishing before replacing a v0.2 installation.

## Share evidence

Prefer sanitized briefs and metadata from COMPLETION.json. Never share credentials, raw transcripts,
private source or raw hook logs automatically. The release evidence document records only synthetic
project details, results and versions. Review all code and PRs before merging them yourself.
