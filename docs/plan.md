Assumptions: README.md is a single new file at the repo root aimed at a human newcomer; it documents the existing flow (write BRIEF.yaml from BRIEF.example.yaml, run `bash scripts/run.sh`, read `docs/REPORT.md` once `docs/RUN_STATE` is terminal) and changes no scripts. `tests/diffbase.sh` tests `scripts/diffbase.sh`, which this task does not touch, so it must simply keep passing.

# Plan: add-readme

1. **readme**
   - slug: `readme`
   - goal: Write README.md at the repo root explaining what quickship is, how to write BRIEF.yaml (from BRIEF.example.yaml: goal, deliverables, success criteria, budgets, permissions), how to run `bash scripts/run.sh`, and where the report ends up (`docs/REPORT.md`, with `docs/RUN_STATE` as the terminal signal).
   - owns: `README.md`
   - needs_web: no
   - depends on: none
   - done when: README.md contains "quickship", "BRIEF.yaml", "scripts/run.sh" and "REPORT.md"; `bash tests/diffbase.sh` exits 0; and the reviewer judges that a newcomer reading README.md alone can start a mission without asking anyone a question (prerequisites, brief fields, run command, where to read results).
