# Decision log

One line per merged task. Append only; never edit past entries.

| Date | Task | Decision | Why |
|---|---|---|---|
| 2026-09-30 | parallel-workers-scaffold | Added planner agent, worktree-based parallel workers, and this decision log | Goals touching >3 files split into file-disjoint tasks so workers can run in parallel without merge conflicts, and every merge leaves an audit trail |
