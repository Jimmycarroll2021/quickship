Assumptions: "as used in this repo" means definitions are derived only from local sources (CLAUDE.md, docs/design/contracts.md, scripts/ledger.py, scripts/overseer.sh, scripts/run.sh, scripts/brief.py); "Mission Brief" is the validated BRIEF.yaml / .claude/state/brief.json; each of the five terms gets exactly two sentences under its own heading.

# Plan: add-docs-glossary

1. **slug:** `docs-glossary`
   - **goal:** Create docs/GLOSSARY.md defining Mission Brief, Task Ledger, Progress Ledger, RUN_STATE and overseer, each in two sentences, derived from the repo's own docs and scripts.
   - **owns:** `docs/GLOSSARY.md`
   - **needs_web:** no
   - **depends on:** none
   - **done when:** `docs/GLOSSARY.md` contains "Mission Brief" and "RUN_STATE" (plus the other three terms), `bash tests/diffbase.sh` exits 0, and `bash scripts/gate.sh` exits 0 from the worktree.
