# Decision log

One line per merged task. Append only; never edit past entries.

| Date | Task | Decision | Why |
|---|---|---|---|
| 2026-09-30 | parallel-workers-scaffold | Added planner agent, worktree-based parallel workers, and this decision log | Goals touching >3 files split into file-disjoint tasks so workers can run in parallel without merge conflicts, and every merge leaves an audit trail |
| 2026-09-30 | brief-schema | Added BRIEF.schema.yaml (JSON-Schema subset in YAML), example brief, jq-based validate_brief.sh | No jsonschema lib available; yq here is the Python jq wrapper, so a small jq validator keeps it dependency-free |
