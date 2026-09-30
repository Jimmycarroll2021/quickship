# Glossary

## Mission Brief
The Mission Brief is the human-written `BRIEF.yaml` (see `BRIEF.example.yaml`) holding the goal, deliverables, success criteria, budgets and permissions for a run. `python3 scripts/brief.py validate` checks it and writes `.claude/state/brief.json`, which the lead re-reads every turn.

## Task Ledger
The Task Ledger is `docs/ledgers/task.json`, managed by `scripts/ledger.py`, which records each task's slug and status (`pending`, `dispatched`, `merged`, `failed`) plus replan and stall counters. The lead loads it on resume to decide which tasks are done and which worktrees to reuse.

## Progress Ledger
The Progress Ledger is the append-only `docs/ledgers/progress.jsonl`, one JSON event per line (such as dispatched, merged, failed, assumption, blocked or replan) written by `scripts/ledger.py append`. The lead and the overseer read it to track tokens, cost and stalls.

## RUN_STATE
`RUN_STATE` is the one-line JSON file `docs/RUN_STATE` of the form `{"state": "DONE|DONE_PARTIAL|SAFE_STOP|HALT", "reason": "...", "at": "..."}`, written by the lead when a run ends. The Stop hook and `scripts/run.sh` read it, and a run without a terminal `RUN_STATE` is treated as still active.

## overseer
The overseer is the watcher process that `scripts/run.sh` starts beside the lead session, implemented in `scripts/overseer.sh`. It monitors the run and signals the lead through the `.claude/state/cancel` and `.claude/state/force_replan` files, and it writes its notes to `docs/overseer.md`.
