# Quickship 0.3.0 release evidence

Status: validation in progress. This document is updated with the final results before the readiness PR is marked ready.

## Scope

Cooperative safeguards for trusted local projects, not an operating-system sandbox. Public release requires both automated regression checks and real Claude Code delivery checks. No release tag, merge or deployment is performed by this work.

## Automated validation

- Local Python hardening checks: 58 passed (one Windows symlink capability test skipped where unavailable).
- Local controller/provider simulations: 19 passed.
- Focused legacy budget, gate, installer and stop cases passed after migration to explicit quality configuration.
- Full suite and Ubuntu/Windows Python 3.10/3.12 CI: pending final run.

## Live validation

A private synthetic repository, `Jimmycarroll2021/quickship-acceptance-20261003`, contains no personal data or production services. Claude Code 2.1.288 uses Claude subscription authentication. Usage credits were disabled before the test; no account or billing settings were changed. Dollar figures are API-equivalent estimates, not subscription charges.

- Initial trials were stopped and preserved after revealing a plan-tier Agent dispatch bug and missing custom-agent discovery under isolated settings. Both received fixes. No PR was published by these trials.
- Small Node mission using frozen CLI agent definitions: DONE after resuming the same saved session to commit a gate-generated lockfile. All final checks passed; test PR #1 has matching branch and PR SHA b924618dc51b64b29b28762db434dd99aa78f65c. The Node gate no longer installs dependencies when none are declared, preventing that lockfile side effect.
- Initial documentation-chain trial was held at DONE_PARTIAL because the reviewer used a judge ordinal instead of the full criterion index. The grader now specifies full indices and accepts ordinal zero only for a sole, unambiguous judge. Final verification also preserves the committed criteria ledger.
- A second documentation trial exposed uppercase/multiline judge responses that the initial parser rejected. The recorder now accepts the real response format and keeps the actual evidence; a regression reproduces that response. Parent-generated PROGRAM.md is permitted as an untracked controller artifact.
- Two-mission PR stack on the corrected harness: running.
- Interruption/resume documentation mission: pending.

## Limits

Project scripts, package managers and arbitrary indirect code execution remain trusted. Hook guards cannot stop code from bypassing them via another process. Independent final verification detects harness changes and refuses publication. Read-only reviewer commands may execute project tests. Use an isolated environment for untrusted repositories.
