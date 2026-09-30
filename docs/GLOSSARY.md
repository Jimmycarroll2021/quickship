# Glossary

Terms used across quickship, defined as this repo uses them.

## Mission Brief

The Mission Brief is `BRIEF.yaml`, written once by the human, and it holds the goal, deliverables, success criteria, budgets, permissions and ambiguity policy. `scripts/brief.py validate` turns it into `.claude/state/brief.json`, which every hook and script reads.

## Task Ledger

The Task Ledger is `docs/ledgers/task.json`, written only by `scripts/ledger.py`, and it holds the goal, the plan, facts, assumptions, blocked steps, `replan_count` and `stall_count`. Each plan entry records a slug, goal, owned files, branch, commit and a status of `pending`, `dispatched`, `merged`, `failed` or `skipped`.

## Progress Ledger

The Progress Ledger is `docs/ledgers/progress.jsonl`, an append-only file with one JSON object per line written by `ledger.py append`. Each line carries `ts`, step id, slug, event (`dispatched`, `merged`, `failed`, `timeout`, `assumption`, `blocked`, `replan`, `stall`, `criteria` or `note`), detail and `state_hash`, and `stall-check` reads it to detect a lack of progress.

## RUN_STATE

RUN_STATE is `docs/RUN_STATE`, a single JSON line of the form `{"state": "DONE|DONE_PARTIAL|SAFE_STOP|HALT", "reason", "at"}` that the lead writes last. The Stop hook and `run.sh` refuse to end or restart an active run unless it holds a terminal state.

## overseer

The overseer is `scripts/overseer.sh`, an independent `claude -p` watchdog that `run.sh` starts beside the lead with `QS_ROLE=overseer`. It reads the ledgers, budget and decisions, appends notes to `docs/overseer.md`, and signals the lead only through the flag files `.claude/state/force_replan` and `.claude/state/cancel`.
