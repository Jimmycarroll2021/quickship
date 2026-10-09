# Contributing to quickship

Thanks for helping. quickship's job is to run software work with nobody watching, so every change is judged on one question: does it keep an unattended run safe, bounded and honest about what happened?

## The most useful contribution: a run that misbehaved

Open an issue with these four things:

1. **The brief.** Your `BRIEF.yaml`, with anything private removed.
2. **The outcome.** `docs/RUN_STATE` and the relevant parts of `docs/REPORT.md`.
3. **The denials.** The `DENY` lines from `.claude/state/hook_log`. They show exactly which guardrail fired and why.
4. **Your environment.** OS, shell (Git Bash, WSL, macOS or Linux), `claude --version`, and Python version.

A run that stalled, looped, overspent, asked for permission it couldn't get, or reported success it didn't have is exactly what we want to hear about.

## Making a change

```bash
git clone https://github.com/Jimmycarroll2021/quickship
cd quickship
bash scripts/gate.sh       # compile check, full self-tests including installation, and secrets scan
```

The full gate is the acceptance entry point; there is no need to run the full suite twice.
Windows self-tests default to one job, and installed-copy tests inherit that limit.
Use `QS_TEST_JOBS=2` for bounded parallelism, or `QS_TEST_JOBS=1` for a serial run.
Standalone harness self-tests have a 90-minute timeout. Set `QS_TEST_LOG_DIR` to a private,
untracked directory to retain per-script output and exit codes; see the runbook for details.

- **Test first.** Every hook and script has a test file in `tests/` using the helpers in `tests/lib.sh`. Add a failing case, watch it fail, then fix the code.
- **Keep the contract in step.** If you change what a script reads, writes or prints, update `docs/design/contracts.md` in the same pull request. The agents read it.
- **Guardrails only get stricter by accident, never looser.** A change that lets a hook allow something it used to deny needs a test for the new allow and an explanation in the pull request.
- **Standard library only** for the Python scripts. PyYAML stays optional.
- **Cross-platform.** CI runs on Ubuntu and Windows (Git Bash). Watch for CRLF output, backslash paths and `python3` vs `python`.
- **Small pull requests** with one logical change each and a message that says why.

## Where things are

`CLAUDE.md` is the agent contract and the lead loop. `scripts/hooks/` holds the guardrails, `scripts/*.py` the ledgers, budgets and criteria, and `.claude/agents/` the subagent prompts. The README's "Project layout" section has the full map.

## Licence

By contributing you agree that your contributions are licensed under the [MIT licence](LICENSE).
