# Quickship 0.3.0 release evidence

Status: validation in progress. This document is updated with the final results before the readiness PR is marked ready.

## Scope

Cooperative safeguards for trusted local projects, not an operating-system sandbox. Public release requires both automated regression checks and real Claude Code delivery checks. No release tag, merge or deployment is performed by this work.

## Automated validation

- Local Python hardening checks: 46 passed (one Windows symlink capability test skipped where unavailable).
- Local controller/provider simulations: 17 passed.
- Focused legacy budget, gate, installer and stop cases passed after migration to explicit quality configuration.
- Full suite and Ubuntu/Windows Python 3.10/3.12 CI: pending final run.

## Live validation

A private synthetic repository, `Jimmycarroll2021/quickship-acceptance-20261003`, contains no personal data or production services. Claude Code 2.1.288 uses Claude subscription authentication. Usage credits were disabled before the test; no account or billing settings were changed. Dollar figures are API-equivalent estimates, not subscription charges.

- Initial trials were stopped and preserved after revealing a plan-tier Agent dispatch bug and missing custom-agent discovery under isolated settings. Both received fixes. No PR was published by these trials.
- Small Node mission using frozen CLI agent definitions: running.
- Two-mission PR stack: pending.
- Interruption/resume documentation mission: pending.

## Limits

Project scripts, package managers and arbitrary indirect code execution remain trusted. Hook guards cannot stop code from bypassing them via another process. Independent final verification detects harness changes and refuses publication. Read-only reviewer commands may execute project tests. Use an isolated environment for untrusted repositories.
