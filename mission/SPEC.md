# Mission Brief runner spec

> **STUB: Replace with the real spec.** This file was inferred from the owner's request because the real `mission/SPEC.md` was not available. Every item below is an assumption, not a requirement from the owner. Do not treat it as authoritative.

## §1 Brief (`mission/BRIEF.yaml`)

Top-level keys (no others allowed):

- `version`: integer, must be 1.
- `goal`: non-empty string.
- `success_criteria`: array, at least one item. Each item has an `id` (`^[a-z0-9][a-z0-9-]*$`) and a `kind`:
  - `test`: `{id, kind, cmd, timeout_s?}`. Passes if `cmd` exits 0. `timeout_s` is an integer >= 1, default 300.
  - `file`: `{id, kind, path, assert?}`. Passes if `path` (repo-relative) exists. `assert` is a jq boolean filter run on the file (`yq -c .` for .yaml/.yml, `jq -c .` for .json) and must output `true`. `assert` on any other extension fails.
  - `judge`: `{id, kind, rubric}`. Judged by an agent, not the gate.
- `deliverables`: array of repo-relative path strings, at least one.
- `budgets`: `{steps: integer >= 1, wall_clock: string matching ^[0-9]+(s|m|h)$}`.
- `permissions`: `{write: [glob], network: boolean, push: "none" | "feature_branch"}`.
- `ambiguity_policy`: `assume_and_log`.
- `reporting` (optional): `{estimate_only: {tokens: integer|null, cost_usd: number|null}}`.

## §2.1 Ledgers (`mission/ledgers/`)

- `task.json`: `{"_header": {...}, "mission": "mission/BRIEF.yaml", "started_at": null | ISO-8601, "entries": []}`. Entry: `{type: ASSUMPTION|DECISION|BLOCKER, ts, step, summary, detail}`. For ASSUMPTION, `summary` is the question and `detail` is the default chosen and why. Append only.
- `progress.jsonl`: one JSON object per line. Line 1 is `{"type":"HEADER","fields":{...}}`. Step records: `{type:"STEP", ts, step, action, status: ok|blocked|failed, detail}`. Append only.

## Termination states

Precedence, highest first:

1. `SAFE_STOP`: STEP lines exceed `budgets.steps`. Exit 0 regardless of other failures.
2. `HALT`: invalid brief, a failed gate check, or a failed criterion. Exit 2.
3. `DONE_PARTIAL`: no failures, at least one judge criterion pending. Exit 0.
4. `DONE`: every criterion passes. Exit 0.

The state word is line 1 of `mission/REPORT.md`.

## Assumptions

1. The field shapes in §1 above (names, types, required keys, patterns) are inferred, not specified.
2. The criterion kinds are `test`, `file` and `judge`, with the fields listed above; `assert` is a jq filter.
3. JSON has no comments, so `task.json` uses a `_header` object and `progress.jsonl` uses a HEADER record as the header.
4. Steps are counted from STEP lines in `progress.jsonl`; HEADER lines are skipped.
5. The termination-state precedence (SAFE_STOP > HALT > DONE_PARTIAL > DONE) and exit codes (0, 0, 0, 2 for HALT) are inferred.
6. Judge verdicts come from marker files: the gate writes `mission/.judge/<id>.pending`, and the lead's `reviewer` writes `mission/.judge/<id>.verdict` whose first line is PASS or FAIL.
7. `mission/REPORT.md` is generated and gitignored, along with `mission/.judge/`.
8. `budgets.wall_clock` is validated for format but not enforced yet.
9. `tokens` and `cost_usd` are estimate-only under `reporting.estimate_only`; they are never enforced.
