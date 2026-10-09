# Quickship release evidence

## v0.3.1 candidate

Status: patch implementation is under verification. This document will record the final source revision,
complete local gate, exact-commit CI and fresh private synthetic live acceptance before a readiness PR is opened.
The existing v0.3.0 release remains unchanged.

The patch addresses cancellation during final verification/publication, unresolved docs-profile bases,
nested self-test concurrency and retained test evidence. The default project timeout and mission budgets
remain bounded; only standalone harness self-tests receive a longer limit.

## Published v0.3.0 baseline

PR #11 was merged and v0.3.0 was published on 2026-10-04 at `a83bd80cb38f01b8570da69947c742eadc10c149`.
The published source tree matches reviewed head `872309da1e4cda8c728d8beb528c059484771ab8`.
All four Windows/Ubuntu Python 3.10/3.12 jobs passed on the published commit.
[Published release](https://github.com/Jimmycarroll2021/quickship/releases/tag/v0.3.0),
[release-commit CI](https://github.com/Jimmycarroll2021/quickship/actions/runs/37177568767).

The historical acceptance below ran on earlier functional revisions. It is not fresh live validation of v0.3.1.

## Historical v0.3.0 acceptance revisions

Quickship remains a cooperative harness for trusted local development projects, not an operating-system sandbox. The implementation separates agent work from authoritative completion and publication, freezes active policy, records actual reviewer/security responses, enforces explicit quality checks and preserves bounded recovery state.

Earlier functional revision: `da293dd2c685d0f56c5b77e6301db24b64fa3396`. The successful live documentation chain installed revision `2f55577d041c632cfbae765c01a74edb5f978dfc`. The subsequent functional change bounds every publication command by the remaining deadline, rechecks that deadline between commands and refuses DONE if publication exceeds it. That change passed focused provider simulations and the complete CI matrix. Further review fixes were included in the published v0.3.0 tree; the earlier live runs are not represented as acceptance of those later changes or v0.3.1.

## Historical automated validation

- Local hardening suite: 58 tests run, 57 passed and one Windows symlink capability test skipped where unavailable.
- Local controller/provider suite: 22 tests passed, including saved-session recovery, publication reconciliation, report restoration and deadline boundaries.
- Full local suite on the frozen `2f55577` revision: all 19 shell test scripts passed. The installer suite avoids recursive installed-suite execution locally; CI also exercises the installed copy.
- Full final-functional-revision CI: Windows and Ubuntu, each with Python 3.10 and 3.12, all passed. [PR CI run](https://github.com/Jimmycarroll2021/quickship/actions/runs/37114430611), [push CI run](https://github.com/Jimmycarroll2021/quickship/actions/runs/37114428738).
- Python compilation and `git diff --check` passed.

These cover cooperative command restrictions, worker ownership, subagent binding, frozen harness integrity, real-review evidence matching, accounting that does not rewind after transcript changes, criteria subprocess timeout, strict quality configuration, installer conflicts, terminal states, crash recovery and duplicate-publication prevention. Simulated providers are identified separately from the live results below.

## Historical live validation

A private synthetic acceptance repository, not published, contains a small Node helper and built-in Node tests, with no personal data or production services. Claude Code 2.1.288 used Claude subscription authentication. Usage credits were disabled before testing; the work changed no billing settings. Dollar counters are API-equivalent estimates, not subscription charges. Live testing took place on Windows with Git Bash; Linux is covered by automated CI.

| Mission | Verified result | Test PR (private repository) | Final branch/PR SHA |
|---|---|---|---|
| Require numeric arguments for the Node sum helper | DONE; five project tests passed | #1, base `main` | `b924618dc51b64b29b28762db434dd99aa78f65c` |
| Explain the sum helper with a usage example | DONE; independent judge evidence matched the source and the project test passed | #2, base `main` | `c69cb4448d0c7e8af6fe9461f8cc606cbe725690` |
| Write numerical examples, after a forced process crash | DONE; documentation criteria and final security checks passed | #3, base `mission/sum-usage-doc` | `6b25977af9eb55e266f17665a7d74a86731b129a` |

The two documentation missions form a verified PR stack. Local heads, remote branch heads and GitHub PR heads match. The controller did not change the synthetic repository's prepared `main` SHA, `785de3bd1462dedb192123ebb88dfc9fbe1f2ddb`, or merge any PR.

### Interruption and recovery

During the second documentation mission, the operator terminated only the owned Claude process tree after the worker had written and committed its document. The supervisor recorded SAFE_STOP. The session, original deadline and worker worktree/commit survived. The normal program launcher skipped the first completed mission and resumed the second in its existing checkout. Its step count increased from 40 at interruption to 96 at completion; it was not reset.

Final verification then caught uncommitted archived first-mission evidence and returned DONE_PARTIAL without publishing. Another invocation of the same launcher resumed the same session, committed that evidence and obtained a fresh security verdict on the new final commit. It subsequently published PR #3 and recorded DONE. This demonstrates recoverable completion; it does not claim that the model never needs a resume after an incomplete handoff.

A final program invocation skipped both DONE missions, returned exit 0 and left the step count unchanged. There are exactly three acceptance PRs, with no duplicate created during retries.

Direct `node` execution was denied to the documentation agents by their tool permissions. The usage reviewer ran `npm test` and matched the source. After delivery, the operator separately executed all nine documented examples against `src/sum.js`, including negative numbers, decimal rounding and string concatenation; all matched. Those direct example checks are operator evidence, not agent evidence.

### Failures retained and fixed

Initial trials were preserved rather than relabelled as successes:

- Plan-tier Agent dispatch was denied; the guard now permits the registered planning workflow.
- Isolated settings did not discover project custom agents; the launcher now loads frozen named definitions through the CLI explicitly.
- Criteria subprocess handling and quoted shell segments failed during integration; corrected handling has regressions.
- The Node gate generated an unnecessary lockfile in a dependency-free project. The same session recovered and committed it; the gate now skips installation when no dependencies are declared.
- A reviewer used a judge ordinal, then another used uppercase/multiline evidence. The recorder now accepts the evidenced response format and resolves ordinal zero only for a sole, unambiguous judge; final verification still requires the actual matching reviewer response.
- GitHub temporarily rate-limited publication. The controller returned ERROR instead of DONE. Retry exposed controller-owned report headings as dirty tracked content; resume now restores only the controller's exact last rendering and preserves later user edits.

Raw synthetic transcripts, trial state and crash snapshots are kept privately by the maintainer and are not published. This document contains only synthetic project metadata and summarized results, so the live rows above cannot be re-checked from public sources.

## Limits and release boundary

Project scripts, dependency installation and indirect code execution remain trusted. Hooks cannot stop code from bypassing them via another process; use isolation for untrusted repositories. Final verification refuses publication after active harness or brief changes. Reviewer commands may execute trusted project tests.

Live acceptance covers a small Node mission and documentation missions on Windows. Ubuntu compatibility has automated evidence. macOS, cloud execution, Python application delivery, every language ecosystem and live overseer operation were not exercised by these acceptance runs; overseer behavior has regression coverage. No production-readiness claim is made for arbitrary projects.

v0.3.0 is published. Any v0.3.1 readiness PR requires human review; merge and release publication are separate actions.
