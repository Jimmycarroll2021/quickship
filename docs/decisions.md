# Decision log

One line per merged task. Append only; never edit past entries.

| Date | Task | Decision | Why |
|---|---|---|---|
| 2026-09-30 | parallel-workers-scaffold | Added planner agent, worktree-based parallel workers, and this decision log | Goals touching >3 files split into file-disjoint tasks so workers can run in parallel without merge conflicts, and every merge leaves an audit trail |
| 2026-09-30 | s1-safe-scaffold | Gate resolves root from its own tree, scans untracked files; hard rules enforced by settings deny list + guard.sh hook; worker loses web tools, researcher added, worker never asks | Gate silently tested main from inside a worktree; cloud sessions do not have ~/.claude rules; a worker with web + push is the lethal trifecta; stop-and-ask is a stall when nobody is there |
