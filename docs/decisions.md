# Decision log

One line per merged task. Append only; never edit past entries.

| Date | Task | Decision | Why |
|---|---|---|---|
| 2026-09-30 | parallel-workers-scaffold | Added planner agent, worktree-based parallel workers, and this decision log | Goals touching >3 files split into file-disjoint tasks so workers can run in parallel without merge conflicts, and every merge leaves an audit trail |
| 2026-09-30 | brief-schema | Added BRIEF.schema.yaml (JSON-Schema subset in YAML), example brief, jq-based validate_brief.sh | No jsonschema lib available; yq here is the Python jq wrapper, so a small jq validator keeps it dependency-free |
| 2026-09-30 | ledgers-spec | Added task.json (_header object) and progress.jsonl (HEADER record) ledgers plus bannered SPEC.md stub | Real spec unavailable; JSON has no comments, so field docs live in a skip-able header record |
| 2026-09-30 | gate | gate.sh evaluates success criteria and writes REPORT.md with DONE/DONE_PARTIAL/SAFE_STOP/HALT; REPORT.md and .judge/ gitignored | Stop hook regenerates the report every stop, so tracking it would dirty the tree; only HALT exits 2 to avoid stop-hook loops |
| 2026-09-30 | docs | CLAUDE.md now describes quickship as reference impl of mission/SPEC.md with assume-and-log ambiguity policy; added CHANGELOG.md | Autonomous runs must not block on questions; CHANGELOG satisfies the example brief's criterion |
| 2026-09-30 | gate-criteria-isolation | Load success_criteria into an array before running any, and run test cmds with </dev/null | Reviewer showed a test cmd could consume the criteria stream (stdin, then fd 3) and produce a false DONE |
