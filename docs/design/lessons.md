# Lessons from published harness work, and what quickship does with them

Sources, read in full in October 2026: Anthropic's "Building effective agents", "Effective harnesses for
long-running agents", "Harness design for long-running apps" and "Effective context engineering for AI agents";
the `autonomous-coding` quickstart in anthropics/claude-quickstarts; the "Claude prompting best practices" page
(long-horizon state tracking); the Claude Code `frontend-design` skill; and the Wikipedia article on generative
adversarial networks, read as an analogy for a generator-and-critic loop.

Status: **has** = already in quickship before this document; **adopted** = added with this document or later
(see CHANGELOG); **backlog** = agreed gap, not yet built; **declined** = judged not worth its complexity here.

## The governing rule

"Find the simplest solution possible, and only increase complexity when needed" (Building effective agents).
quickship is an orchestrator-workers workflow (lead, planner, file-disjoint workers) wrapped around an
evaluator-optimizer loop (reviewer, security) with a controller that holds the ground truth (gate, criteria,
publication). Each of those is on the post's list of patterns worth their cost for coding work. The rule is
applied here in two directions: a published lesson is adopted only where quickship lacks the behaviour, and a
quickship component with no effect is either wired up or named for removal rather than left in place.

## Context and handoff

| Lesson | Source | Status | Where |
|---|---|---|---|
| Carry state across context windows in files, not compaction: a freeform progress note, structured state, git | harness post; prompting guide | adopted | `ledger.py handoff`, `docs/ledgers/handoff.md`, `hooks/anchor.sh` |
| Structured state in JSON because the model edits it less casually than Markdown | harness post | has | `task.json`, `progress.jsonl`, `criteria.json` |
| Prescriptive session start: read the notes and the log, then run a fundamental check before new work | prompting guide; quickstart step 1 and 3 | adopted | lead loop step 1 (gate on resume), anchor closing instruction |
| A different prompt for the first context window | prompting guide; harness post | has | the planner runs once in the plan tier; later contexts start from the anchor |
| One small unit per session, left in a merge-ready state with a commit and a note | harness post; quickstart | has (per task and per mission); adopted (note after every merge or failure) | planner task rules, PR size target, lead loop step 5 |
| Do not run out of context with significant uncommitted work | prompting guide | adopted | `budget_hook.py` allows a single `git add`, `git commit` or `ledger.py handoff` once a budget is exhausted |
| One number for "wrap up now" | own audit | adopted | `budget.NEAR_FRACTION` = 75%; `CLAUDE.md` step 3, the controller prompt and the per-call BUDGET `near=` hint all mean it |
| Start script that avoids rediscovering how to run and test the app | harness post; prompting guide | has | `gate.sh` stack detection and the brief's `quality` commands |
| Deliberate context resets between units are no longer needed on Opus 4.5 and later; one continuous session with compaction held for hours | harness design post | has | the controller resumes the same session; handoff files exist for crashes and compaction, not as a reset schedule |
| Decompose into sprints only while the model needs it; stress-test every harness component as models improve | harness design post | has (tasks are the unit, their size is the planner's call) | planner rules; see the simplification backlog below |
| Context is a finite attention budget: the smallest set of high-signal tokens; a fresh window gets the summary plus the most recently accessed files | context engineering post | adopted | the anchor pack is capped at 9000 characters and now carries `<recent-files>` (uncommitted changes, then the last three commits, five paths) with "read these first, fetch the rest as needed" |
| Tool results bloat the window; clear or thin what is not signal | context engineering post | adopted | the BUDGET readout after every tool call now prints every tenth step and whenever a budget is near or exhausted, instead of on every call |
| Just-in-time retrieval over lightweight identifiers rather than pre-loading | context engineering post | has | the anchor injects slugs, statuses and paths, not file contents; agents use Read, Glob and Grep on demand |
| Structured note-taking outside the window, read back after a reset | context engineering post | has | ledgers in JSON, `handoff.md` in prose, `decisions.md` |
| Sub-agents keep detailed exploration in their own window and return a condensed result | context engineering post | has | worker returns three lines and paths, reviewer a verdict list, planner a path and a count, researcher one file path |
| System prompt at the right altitude: concrete heuristics, not brittle branching or vague guidance; start minimal, add on observed failures | context engineering post | has, with one deliberate exception | the lead loop is a numbered procedure because tools enforce its steps; the agent prompts are heuristics plus one canonical example each |

## Orchestration and evaluation

| Lesson | Source | Status | Where |
|---|---|---|---|
| Orchestrator-workers for multi-file changes; parallel only when workstreams are independent | Building effective agents; prompting guide | has | lead and planner, file-disjoint worktrees |
| Evaluator-optimizer only with clear criteria; the grader is independent, has a fixed rubric and quotes evidence | Building effective agents; GAN analogy (weak discriminator misses omissions) | has | reviewer and security are read-only subagents; judge grades need the frozen rubric, current artefact hashes and evidence |
| A quiesced generator-critic loop is not "done"; an external, frozen metric decides | GAN analogy (local equilibrium is not convergence) | has | the controller reruns gate, criteria and security on the final commit; agent verdicts never establish DONE |
| Findings must be actionable, graded steps, not a flat reject | GAN analogy (vanishing gradient) | has | reviewer output format `file:line: what is wrong: which rule` |
| Bound the rounds, detect stalls | Building effective agents (stopping conditions) | adopted | `stall_limit`, `replan_limit` enforced; the lead loop now uses `critic_rounds` as the fix-and-re-review bound instead of a literal "three times" |
| The overseer's `force_replan` request must reach an actor that can act on it | own audit | adopted | lead loop step 6; `ledger.py replan` clears the flag |
| Human checkpoints at the irreversible edge | Building effective agents | has | the controller publishes a PR; the human owns the merge |
| Tool design is the agent-computer interface: poka-yoke the arguments | Building effective agents | has | one command per call, relative paths, `step-bind` first, `git -C` |
| Multi-agent is not shown to beat one good agent; add roles only for a measured failure | harness post (open question) | has | seven roles, each tied to a named failure in the track record; no routing by task type on purpose |
| Agree what "done" means before code: a contract of testable behaviours the evaluator reviews first | harness design post | adopted | the brief's criteria are frozen before the run; each planned task's `done when` is now a command or a criterion index, and the reviewer grades every merged task against it. No pre-review round: the contract is structural, not negotiated |
| The planner is ambitious at product altitude and leaves implementation to the workers; granular technical decisions in the spec cascade | harness design post ("without the planner, the generator under-scoped") | adopted | PRD gains a Product vision section the MVP is cut from; the strategist stays at product context and high-level design; task goals name outcomes, not paths |
| A standalone, skeptical evaluator is more tractable than a self-critical generator; it still tends to approve despite the defects it found and to test the happy path | harness design post | adopted | reviewer is separate and read-only; its prompt now says a defect it found is a FAIL item and to probe edge cases, not the happy path |
| Calibrate the evaluator with few-shot graded examples to stop score drift | harness design post | declined for now | grades are PASS or FAIL per criterion with quoted evidence, which drifts less than scores; revisit if judge grades disagree with human review |
| Agents talk through files, not shared context | harness design post | has | plan.md, ledgers, handoff.md, worker summaries |

## Verification

| Lesson | Source | Status | Where |
|---|---|---|---|
| Tests are immutable from the agent's side: never remove or edit them to pass | harness post; prompting guide; quickstart | adopted | criteria are frozen in the brief; the worker may not delete, skip or weaken an existing test; the reviewer fails a diff that does |
| Verify end to end as a user would, through the UI for UI work | harness post; quickstart | adopted | strategist requires a Playwright criterion for UI missions; the sandbox network allowlist admits Playwright's browser download hosts |
| Tests verify, they do not define the solution; report an unreasonable test instead of gaming it | prompting guide | adopted | worker prompt |
| Give the planner a design language for UI products so taste is specified before code, not improvised by the worker | harness design post (planner read the frontend-design skill); frontend-design skill | adopted | "Design language" section in `docs/PRD_TEMPLATE.md`, filled by the strategist; the judge rubric can cite it |

## Declined, with reasons

- **A separate "memory" or summariser agent.** The files above are the memory. Another agent would be a second
  source of truth.
- **Routing by task type and installable skills (for example `frontend-design`).** The skill's transferable
  idea is a reviewable plan before code and a falsifiable anti-pattern list. The strategist and planner already
  produce the plan; the reviewer already works from a fixed rubric. A per-stack prompt library would be a new
  surface to keep correct, with no failure in the track record to justify it. Revisit if UI missions fail review
  on taste rather than tests.
- **An adaptive critic that learns from the worker.** The GAN analogy breaks exactly here: a moving grader
  invites collusion and a loop that never settles. The grader stays frozen for the run.
- **Scheduled context resets.** The harness design post dropped them once Opus 4.5 stopped wrapping up early
  near its context limit, and notes each reset costs orchestration, tokens and latency. quickship keeps one
  session and writes handoff notes so a crash or compaction loses nothing; it does not reset on a schedule.
- **Unbounded sessions ("you have unlimited time").** The quickstart's loop has no stop condition; quickship's
  budgets, deadline and launch cap are the stop conditions the effective-agents post asks for.

## Simplifications this audit recommends (backlog)

Each is a component whose effect is zero or duplicated; remove it in a release that also drops the v0.2
compatibility path, with its tests.

- `hooks/idem.sh`: agents cannot push, open PRs or call MCP in a controller run, and the controller has its own
  publication reservation.
- `hooks/stop.sh` lines for the v0.2 RUN_STATE path.
- `check_criteria.py --judge`: the controller trusts only the hook-captured grade.
- Hard rules written three times (settings deny list, `guard.sh`, `policy.py`): keep `policy.py` as the one
  source and generate the other two.
- The overseer as a model call: it applies four thresholds a script could apply.
