# Plan: Mission Brief runner, slice 1

Session branch: `claude/youthful-meitner-yzpyv7`. Worktrees: `.claude/worktrees/<slug>`, branch `claude/youthful-meitner-yzpyv7--<slug>`.

All four tasks are independent and run in parallel. None depends on another's output at dispatch time. The files they own do not overlap. Every task follows the Contract below exactly.

1. **brief-schema**
   - goal: Write the brief schema, the example brief and a jq-based validator that checks the brief against the schema, all as the Contract specifies.
   - owns: `mission/BRIEF.schema.yaml`, `mission/BRIEF.yaml`, `scripts/validate_brief.sh`
   - done when: `bash scripts/validate_brief.sh` exits 0 and prints `brief: VALID` on stderr for `mission/BRIEF.yaml`. A mutated copy exits 2 with one `$.path: message` line per error. Test with an unknown top-level key, `budgets.tokens`, a bad criterion `id` and a `kind: file` item missing `path`, passing the mutated copy as the first argument from the scratchpad and not committing it.

2. **ledgers-spec**
   - goal: Create the initial append-only ledgers, plus a `mission/SPEC.md` stub with a clear banner. The stub records the inferred §1 (brief), the inferred §2.1 (ledgers), the termination states (DONE, DONE_PARTIAL, SAFE_STOP, HALT) and a list of every assumption.
   - owns: `mission/ledgers/task.json`, `mission/ledgers/progress.jsonl`, `mission/SPEC.md`
   - done when: `jq -e '._header and .mission=="mission/BRIEF.yaml" and .started_at==null and .entries==[]' mission/ledgers/task.json` succeeds. The only line in `progress.jsonl` is a valid `{"type":"HEADER","fields":{...}}` record. `mission/SPEC.md` opens with a STUB banner containing the text "Replace with the real spec" and has sections for §1, §2.1, termination states and assumptions.

3. **gate**
   - goal: Extend `scripts/gate.sh` to record a result line per check. When `mission/BRIEF.yaml` exists, it validates the brief, enforces the step budget, evaluates the success criteria and writes `mission/REPORT.md` with the termination state, as the Contract specifies. Also add `mission/REPORT.md` and `mission/.judge/` to `.gitignore`.
   - owns: `scripts/gate.sh`, `.gitignore`
   - notes: This must work before task 1 is merged. Test inside the worktree using your own temporary `mission/BRIEF.yaml`, `mission/BRIEF.schema.yaml`, `scripts/validate_brief.sh` and ledger stubs. Do NOT commit those stubs; remove them or leave them unstaged before committing. Only `scripts/gate.sh` and `.gitignore` may appear in the commit.
   - done when: With the stubs, the gate produces each of the following, and line 1 of REPORT.md is the state word each time:
     - DONE: exit 0. Needs all criteria passing.
     - DONE_PARTIAL: exit 0. Needs a judge criterion with no verdict, which also writes `mission/.judge/<id>.pending`.
     - SAFE_STOP: exit 0. Needs more STEP lines than `budgets.steps`.
     - HALT: exit 2. Needs a validator that fails, or a criterion that fails.

     With no `mission/BRIEF.yaml`, the gate behaves as before and writes no REPORT.md.

4. **docs**
   - goal: Update `CLAUDE.md` and create `CHANGELOG.md` so they describe the mission brief runner.
   - owns: `CLAUDE.md`, `CHANGELOG.md`
   - details:
     - **CLAUDE.md "## What this is":** Rewrite it. quickship is a Claude Code reference implementation of `mission/SPEC.md`: a mission brief runner with a YAML brief (success criteria and budgets), append-only ledgers, and a gate that evaluates the criteria and writes `mission/REPORT.md` with a termination state of DONE | DONE_PARTIAL | SAFE_STOP | HALT.
     - **CLAUDE.md "## Ambiguity policy":** Remove the "must not guess — ask" guidance and add this new section in its place. Agents never ask. They choose a sensible default, append an entry `{"type":"ASSUMPTION","ts":...,"step":...,"summary":<question>,"detail":<default chosen + why>}` to `entries` in `mission/ledgers/task.json`, and continue.
     - **CLAUDE.md "## Mission runner":** Add this short section. It covers:
       - how to run `bash scripts/gate.sh` and `bash scripts/validate_brief.sh [brief] [schema]`
       - what each state means and its exit code
       - that on DONE_PARTIAL the lead runs `reviewer` to write `mission/.judge/<id>.verdict` (first line PASS or FAIL)
       - that agents append one STEP line per step to `mission/ledgers/progress.jsonl`
     - **CLAUDE.md, rest of the file:** In "## Commands", add only a note about `scripts/validate_brief.sh`. Leave every other section unchanged.
     - **CHANGELOG.md:** Use the Keep a Changelog format. Under `## [Unreleased]`, add a `### Added` entry for the mission brief runner (brief schema, validator, ledgers, gate termination states).
   - done when: `CLAUDE.md` contains "## What this is" with the new description, "## Ambiguity policy" and "## Mission runner". It no longer contains "must not guess". `CHANGELOG.md` exists with `## [Unreleased]` and `### Added`, which satisfies the example brief's `changelog-exists` criterion.

## Contract (inferred — the real mission/SPEC.md was not available; every item here is an ASSUMPTION)

### Brief (mission/BRIEF.yaml), spec §1 as inferred
Top-level keys (additionalProperties: false):
- `version`: integer, const 1 (required)
- `goal`: non-empty string (required)
- `success_criteria`: array, minItems 1 (required). Each item is one of three variants, chosen by `kind`; each variant has additionalProperties: false:
  - `{id, kind: "test", cmd: string, timeout_s?: integer >= 1 (default 300)}`. Passes if `cmd` exits 0.
  - `{id, kind: "file", path: string, assert?: string}`. Passes if `path` (relative to the repo root) exists. If `assert` is given, it is a jq boolean filter evaluated on the file (via `yq -c .` for .yaml/.yml, `jq -c .` for .json) and must output `true`. `assert` on any other extension → FAIL.
  - `{id, kind: "judge", rubric: string}`. The gate can't judge, so it writes the marker `mission/.judge/<id>.pending` (containing the rubric) and reports PENDING_JUDGE. If `mission/.judge/<id>.verdict` exists, its first line (`PASS` or `FAIL`) is the result. The lead runs the `reviewer` agent to write verdicts.
  - `id`: string matching `^[a-z0-9][a-z0-9-]*$`, required in all variants.
- `deliverables`: array of strings (repo-relative paths), minItems 1 (required)
- `budgets`: object, additionalProperties false (required): `steps` integer >= 1 (required), `wall_clock` string matching `^[0-9]+(s|m|h)$` (required). NO tokens/cost_usd here.
- `permissions`: object, additionalProperties false (required): `write` array of glob strings (required), `network` boolean (required), `push` enum ["none","feature_branch"] (required)
- `ambiguity_policy`: enum ["assume_and_log"] (required)
- `reporting`: object (optional), additionalProperties false: `estimate_only`: object, additionalProperties false: `tokens`: integer or null, `cost_usd`: number or null. These are informational estimates, never enforced.

### Schema file (mission/BRIEF.schema.yaml)
A JSON-Schema-style document in YAML, using ONLY these keywords (the validator implements only these): `type` (string or array of: object, array, string, integer, number, boolean, null), `required`, `properties`, `additionalProperties` (false only), `items`, `minItems`, `minLength`, `enum`, `const`, `pattern`, `minimum`, `oneOf`, `description`. No `$ref`/`$defs`; inline everything. The success_criteria item variants use `oneOf`, and each variant pins `properties.kind.const`.

### scripts/validate_brief.sh
Usage: `scripts/validate_brief.sh [brief] [schema]`, defaulting to mission/BRIEF.yaml and mission/BRIEF.schema.yaml relative to the repo root (`CLAUDE_PROJECT_DIR`, or the script's parent dir). It converts both to JSON with `yq -c .` (Python yq, a jq wrapper), then validates with an embedded recursive jq function implementing the keywords above. For `oneOf`, if exactly one variant pins `properties.kind.const` equal to the data's `kind`, it reports that variant's errors; otherwise it reports the count of variants matched. Exit 0 + "brief: VALID" on stderr; exit 2 + one error per line on stderr (`$.path: message`). A missing file or a yq parse error → exit 2.

### Ledgers (spec §2.1 as inferred)
- `mission/ledgers/task.json`: JSON has no comments, so the "header comment" is a `_header` object describing the fields. Initial content: `{"_header": {...field descriptions...}, "mission": "mission/BRIEF.yaml", "started_at": null, "entries": []}`. Entry shape: `{"type": "ASSUMPTION"|"DECISION"|"BLOCKER", "ts": ISO-8601 UTC, "step": integer, "summary": string, "detail": string}`. For ASSUMPTION, `summary` is the question and `detail` is the default chosen + why. Agents append to `entries`; they never edit or delete.
- `mission/ledgers/progress.jsonl`: one JSON object per line. The first line is a header record `{"type":"HEADER","fields":{...descriptions...}}`, which consumers skip. Step records: `{"type":"STEP","ts":ISO-8601 UTC,"step":integer,"action":string,"status":"ok"|"blocked"|"failed","detail":string}`. Steps used = the number of `type=="STEP"` lines. Blocked steps = STEP lines with status "blocked".

### Gate extension (scripts/gate.sh)
Existing checks (secrets, lint/test/build) are unchanged, but each records a result line, e.g. `secrets: PASS`, `lint: FAIL`, or `stack: SKIPPED (none detected)`. After them, ONLY if mission/BRIEF.yaml exists:
1. Run scripts/validate_brief.sh; if it fails → state HALT.
2. Count steps from progress.jsonl. If steps > budgets.steps → state SAFE_STOP, and the gate exits 0 no matter what else failed.
3. Otherwise evaluate every success_criteria item → PASS | FAIL | PENDING_JUDGE.
4. State: SAFE_STOP (budget) > HALT (invalid brief, any check FAIL, or any criterion FAIL) > DONE_PARTIAL (no FAIL, ≥1 PENDING_JUDGE) > DONE (everything PASS).
5. Write mission/REPORT.md. Line 1 is exactly the state word. Then `# Mission report`, the goal, a UTC timestamp, `Steps: n / budget`, `## Assumptions` (task.json entries with type ASSUMPTION, selected with jq; "None logged." if empty), `## Blocked steps` (from progress.jsonl; "None." if empty), `## Gate results` (the check result lines), `## Success criteria` (a table: id | kind | result | detail).
6. Exit codes: DONE / DONE_PARTIAL / SAFE_STOP → 0, HALT → 2 (failures on stderr, as now). With no BRIEF.yaml, behave exactly as before and write no report.
Generated files mission/REPORT.md and mission/.judge/ are gitignored (the Stop hook regenerates them on every stop).

### Example brief
goal "add a CHANGELOG.md"; one criterion `{id: changelog-exists, kind: file, path: CHANGELOG.md}`; deliverables [CHANGELOG.md]; budgets {steps: 20, wall_clock: 30m}; permissions {write: ["CHANGELOG.md","mission/**"], network: false, push: feature_branch}; ambiguity_policy assume_and_log; reporting.estimate_only {tokens: null, cost_usd: null}. CHANGELOG.md itself is created (a Keep-a-Changelog file with an Unreleased section noting the mission brief runner) so the example mission is actually DONE.
