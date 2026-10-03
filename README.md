# quickship

Quickship runs a bounded Claude Code mission and hands back a verified pull request.
Write a brief, launch it, then review the code and evidence. A lead plans work, workers use
Git worktrees, reviewers check it, and a separate launcher verifies the result and publishes.

**v0.3 is a cooperative development harness, not a security sandbox.** Use trusted projects
and dependencies in a development checkout. Project scripts execute with your operating-system
access. Hooks reduce accidental mistakes; they cannot make hostile code safe.

## Quickstart

Requirements: Git, Python 3.10+, Claude Code >=2.1.288 logged in, authenticated GitHub CLI,
and bash 4+. Supported CI platforms: Ubuntu and Windows with Git Bash. macOS/cloud execution
are not release-verified. No Python packages are required by the harness.

```bash
git clone https://github.com/Jimmycarroll2021/quickship
bash quickship/scripts/init.sh /path/to/project
cd /path/to/project
# Edit the seeded BRIEF.yaml for your project and commit it.
git add BRIEF.yaml
git commit -m "mission brief"
python scripts/preflight.py
bash scripts/run.sh
```

Windows PowerShell: `quickship\init.cmd C:\path\to\project`, then `.\run.cmd` in that project.
The wrappers locate Git Bash. Claude's native PowerShell tool is disabled for missions.
Resolve any `.quickship/conflicts` before launching. Preflight checks authentication and
capabilities without model calls or account changes.

## Mission brief

```yaml
mission:
  goal: "Add input validation to the calculator"
  deliverables:
    - src/calculator.js
    - test/calculator.test.js
success_criteria:
  - {kind: test, cmd: "npm test", expect: 0}
  - {kind: file, path: src/calculator.js}
budgets:
  tokens: 3000000
  cost_usd: 30
  wall_clock_min: 45
  steps: 160
permissions:
  irreversible:
    default: skip-and-record
    allow:
      - "git push origin mission/*"
      - "gh pr create*"
ambiguity_policy: choose-default-and-record
quality:
  profile: code
  lint: "npm run lint"
  test: "npm test"
  build:
    skip: "This source-only library has no build artifact"
```

All budget dimensions are positive numbers. Optional stall_limit, replan_limit, critic_rounds
retain defaults 3, 5, 2. File criteria accept must_contain (regex); grep criteria need path/pattern;
judge criteria need a rubric and an independently evidenced reviewer verdict. Use block mappings
for skip reasons; both the built-in YAML reader and optional PyYAML accept the example.

### Quality requirements

Node defaults to its package-manager lint/test/build scripts. Missing scripts fail unless
quality provides commands or explicit skip reasons. Python defaults to Ruff, pytest, and a
build if pyproject.toml declares a build system. Install your project tools before launching.
Unsupported stacks require explicit quality entries. Dependency installation and project
commands are trusted operator code, not sandboxed execution.

For docs-only missions set `quality.profile: docs`. The gate rejects application-code changes.
You can still supply a test command for documentation. `BRIEF.example.yaml` is a docs example.
The harness's own gate compiles scripts and runs `bash tests/run.sh`. Installed copies skip the
harness tests unless `QS_SELFTEST=1`; project tests still run.

### Budgets and subscriptions

Tokens count input, output and cache creation; cache reads are reported separately. All lead
and discovered subagent/watchdog transcripts count. Accounting consumes complete transcript lines
incrementally and does not stop at a file-size cutoff. Missing accounting is an error.

On Claude Pro/Max, cost_usd caps an **estimated API-equivalent amount**, not your subscription bill.
Time, token and tool-attempt limits still apply. Quickship never changes your billing settings,
adds credits or switches authentication. Check that extra paid usage is disabled if you want to
use only your subscription. When your plan runs out, stop and resume after capacity returns.

On API authentication the launcher also supplies the remaining --max-budget-usd across resumes;
its hook accounting remains an estimate, not an invoice. A wall-clock supervisor terminates its
owned process tree on deadline/cancellation. In-flight API calls and platform scheduling can
overshoot exact limits. It does not promise an exact dollar/token ceiling.

## What is enforced

- Agents cannot directly push, open/merge PRs, deploy or use external MCP connectors.
- The controller checks the brief's irreversible allow patterns before publishing. An allow
  pattern cannot override the hard prohibitions.
- Direct real .env access and production-config writes are denied, including literal shell
  redirections. Unsupported shell evaluation is refused. Workers write only assigned files
  in their worktree; researchers write only their assigned untrusted findings file.
- Active harness/brief integrity is checked again before publishing. `maintenance: true` permits
  staging owned harness edits in task worktrees. Merging changes into the active harness halts
  publication; apply reviewed updates outside an active run and start a fresh run.
- Concurrent counters and ledgers are serialized; subagents bind to a registered step using agent_id.

These controls are cooperative. Arbitrary project scripts, test runners and dependency installers
can perform side effects outside these checks. A hostile agent/project needs OS isolation,
restricted credentials and network policy; this release does not provide those.

## Verified completion

Agents submit docs/RESULT.json and a report. Only the controller writes docs/RUN_STATE and
COMPLETION.json. Before DONE it independently reruns the gate and objective criteria, requires
all deliverables, evidenced judge grades, a security-agent PASS for the final commit, a clean
tracked worktree, and verifies the remote branch SHA and PR head/base.

| State | Meaning | Launcher exit |
|---|---|---|
| DONE | All final checks and actual PR verified | 0 |
| DONE_PARTIAL | Budget/policy/verification prevented completion | 3 |
| SAFE_STOP | Cancellation, interruption or restart limit | 3 |
| HALT | Policy/integrity violation | 4 |
| ERROR | Controller or verification infrastructure failed | 5 |

Invalid setup or brief exits 2 before model work. An agent saying DONE or a successful Claude
process exit is insufficient. Partial runs may have no PR; their report explains why.

Read docs/REPORT.md and docs/COMPLETION.json. The latter contains gate/criteria/security and
publication evidence. Runtime logs are local under .claude/state and must not be shared raw
when they contain private project information.

## Resume and mission chains

Run the same command again after a crash or interruption. The launcher preserves sessions,
ledgers, reservations and the original deadline. Re-running a verified DONE does not republish.
A missing remote session is reported rather than silently starting a duplicate mission.
Changing an active brief is refused; archive that run explicitly before starting a replacement.
Legacy v0.2 active state is preserved and cannot be resumed automatically by v0.3.

From an idea, write IDEA.md, run `bash scripts/idea.sh`, review its PRD and generated briefs,
then `bash scripts/program.sh`. Each mission's PR targets its predecessor. Chains advance only
on launcher exit 0 and verified DONE. You review/merge the resulting stack first PR first.
Quickship never merges it.

## Installation and upgrades

`bash scripts/init.sh <project> --upgrade` refreshes unmodified managed files. Modified files and
custom CLAUDE.md/settings are preserved; unresolved differences are listed in .quickship/conflicts.
An incomplete upgrade retains the previous installed version. Checksums record actual target files,
not newer source files that were skipped. Resolve conflicts deliberately before launching.
`--force` still preserves custom CLAUDE.md. Do not upgrade an active run.

## Tests and release evidence

`bash tests/run.sh` runs simulated acceptance/regression tests without model calls. CI exercises
Ubuntu and Windows with Python 3.10 and 3.12. It checks guardrails, installation, state, budgets,
quality, completion, deadline behavior and mission-chain semantics. See docs/RELEASE-EVIDENCE.md
for the current release's automated and live evidence; passing simulated tests alone does not
establish real delivery reliability.

Historical v0.1/v0.2 example runs are retained under examples/briefs and docs/runs. Their reports
are historical evidence and use older guard/budget/termination behavior. Do not treat them as
validation of v0.3. The MIT license remains unchanged.
