Assumptions: "overseer" is the process `scripts/run.sh` starts beside the lead session; "Mission Brief" is `BRIEF.yaml` validated into `.claude/state/brief.json`; "Task Ledger" is `docs/ledgers/task.json`; "Progress Ledger" is the append-only event log the lead writes with `ledger.py append`; "RUN_STATE" is `docs/RUN_STATE`. The worker checks these readings against `docs/design/contracts.md`. Nothing but `docs/GLOSSARY.md` changes.

# Plan

1. **add-glossary**
   - slug: `add-glossary`
   - goal: Add docs/GLOSSARY.md defining the terms Mission Brief, Task Ledger, Progress Ledger, RUN_STATE and overseer as used in this repo, each in two sentences.
   - owns: `docs/GLOSSARY.md`
   - needs_web: no
   - depends on: none
   - done when: `docs/GLOSSARY.md` exists and defines all five terms in two sentences each; it contains "Mission Brief" and "RUN_STATE"; `bash tests/diffbase.sh` exits 0.
