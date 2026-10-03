# Quickship 0.3.0 release evidence

Status: release-readiness implementation and validation complete on 2026-10-03. The changes are prepared for review in PR #11; no merge, release tag or deployment has been performed.

## Scope and revisions

Quickship remains a cooperative harness for trusted local development projects, not an operating-system sandbox. The implementation separates agent work from authoritative completion and publication, freezes active policy, records actual reviewer/security responses, enforces explicit quality checks and preserves bounded recovery state.

Final functional revision: `da293dd2c685d0f56c5b77e6301db24b64fa3396`. The successful live documentation chain installed revision `2f55577d041c632cfbae765c01a74edb5f978dfc`. The subsequent functional change bounds every publication command by the remaining deadline, rechecks that deadline between commands and refuses DONE if publication exceeds it. That change passed focused provider simulations and the complete CI matrix. The earlier successful Node mission exercised the same controller design before the integration fixes below; it is not represented as an end-to-end run of the final revision.

## Automated validation

- Local hardening suite: 58 tests run, 57 passed and one Windows symlink capability test skipped where unavailable.
- Local controller/provider suite: 22 tests passed, including saved-session recovery, publication reconciliation, report restoration and deadline boundaries.
- Full local suite on the frozen `2f55577` revision: all 19 shell test scripts passed. The installer suite avoids recursive installed-suite execution locally; CI also exercises the installed copy.
- Full final-functional-revision CI: Windows and Ubuntu, each with Python 3.10 and 3.12, all passed. [PR CI run](https://github.com/Jimmycarroll2021/quickship/actions/runs/37114430611), [push CI run](https://github.com/Jimmycarroll2021/quickship/actions/runs/37114428738).
- Python compilation and `git diff --check` passed.

These cover cooperative command restrictions, worker ownership, subagent binding, frozen harness integrity, real-review evidence matching, accounting that does not rewind after transcript changes, criteria subprocess timeout, strict quality configuration, installer conflicts, terminal states, crash recovery and duplicate-publication prevention. Simulated providers are identified separately from the live results below.

## Live validation

The private synthetic repository `Jimmycarroll2021/quickship-acceptance-20261003` contains a small Node helper and built-in Node tests, with no personal data or production services. Claude Code 2.1.288 used Claude subscription authentication (Max). Usage credits were disabled before testing; the work changed no billing settings. Dollar counters are API-equivalent estimates, not subscription charges. Live testing took place on Windows with Git Bash; Linux is covered by automated CI.

| Mission | Verified result | Private test PR | Final branch/PR SHA |
|---|---|---|---|
| Require numeric arguments for the Node sum helper | DONE; five project tests passed | [#1](https://github.com/Jimmycarroll2021/quickship-acceptance-20261003/pull/1), base `main` | `b924618dc51b64b29b28762db434dd99aa78f65c` |
| Explain the sum helper with a usage example | DONE; independent judge evidence matched the source and the project test passed | [#2](https://github.com/Jimmycarroll2021/quickship-acceptance-20261003/pull/2), base `main` | `c69cb4448d0c7e8af6fe9461f8cc606cbe725690` |
| Write numerical examples, after a forced process crash | DONE; documentation criteria and final security checks passed | [#3](https://github.com/Jimmycarroll2021/quickship-acceptance-20261003/pull/3), base `mission/sum-usage-doc` | `6b25977af9eb55e266f17665a7d74a86731b129a` |

The two documentation missions form a verified PR stack. Local heads, remote branch heads and GitHub PR heads match. The controller did not change the synthetic repository's prepared `main` SHA, `785de3bd1462dedb192123ebb88dfc9fbe1f2ddb`, or merge any PR.

### Interruption and recovery

During the second documentation mission, the operator terminated only the owned Claude process tree after the worker had written and committed its document. The supervisor recorded SAFE_STOP. The session `74508187-045c-492f-a498-c25f03aff720`, original deadline and worker worktree/commit survived. The normal program launcher skipped the first completed mission and resumed the second in its existing checkout. Its step count increased from 40 at interruption to 96 at completion; it was not reset.

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

Raw synthetic transcripts, trial state and crash snapshots remain private in `C:\Users\Jimmy\quickship-acceptance-evidence-20261003`. The public evidence contains only synthetic project metadata and summarized results.

## Limits and release boundary

Project scripts, dependency installation and indirect code execution remain trusted. Hooks cannot stop code from bypassing them via another process; use isolation for untrusted repositories. Final verification refuses publication after active harness or brief changes. Reviewer commands may execute trusted project tests.

Live acceptance covers a small Node mission and documentation missions on Windows. Ubuntu compatibility has automated evidence. macOS, cloud execution, Python application delivery, every language ecosystem and live overseer operation were not exercised by these acceptance runs; overseer behavior has regression coverage. No production-readiness claim is made for arbitrary projects.

The readiness PR is prepared for human code review. Merge and release publication are separate actions.
