# Decision log

One line per merged task. Append only; never edit past entries.

| Date | Task | Decision | Why |
|---|---|---|---|
| 2026-09-30 | parallel-workers-scaffold | Added planner agent, worktree-based parallel workers, and this decision log | Goals touching >3 files split into file-disjoint tasks so workers can run in parallel without merge conflicts, and every merge leaves an audit trail |
| 2026-09-30 | s1-safe-scaffold | Gate resolves root from its own tree, scans untracked files; hard rules enforced by settings deny list + guard.sh hook; worker loses web tools, researcher added, worker never asks | Gate silently tested main from inside a worktree; cloud sessions do not have ~/.claude rules; a worker with web + push is the lethal trifecta; stop-and-ask is a stall when nobody is there |
| 2026-09-30 | s2-core-swarm | Eight file-disjoint tasks (brief, ledger, budget, stop hook, idem, anchor, criteria, overseer) built in parallel worktrees and merged; guard gained cancel/tier/trifecta; run.sh launcher; overseer sessions carry QS_ROLE=overseer | Contracts doc let workers build to one schema without shared files; the overseer shares the repo so its own Stop hook would otherwise SAFE_STOP the lead |
