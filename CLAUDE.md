# quickship

Take a raw idea and get to a demo somebody can open, click through and feel, with nothing half-baked: no dead buttons, no placeholder text, no empty first screen. That is the whole job.

## The one rule
`bash scripts/smoke.sh` is the only thing that says PASS. It boots `./demo.sh`, waits for the health path, runs the smoke spec, and scans for secrets and stubs. No agent declares the demo done, and no report counts as evidence. If it fails, fix the cause, never the check.

## Four stages, run by the human in order
1. `/shape` — the `shaper` turns `IDEA.md` into `DEMO_SPEC.md`: pitch, run, health, stack, seed data, golden path, out of scope. Read it before building.
2. `/build` — the `builder` builds the golden path end to end in the shared tree, writes `./demo.sh` and the smoke spec, and runs the gate. Then `/simplify`.
3. `/verify` — the read-only `verifier` runs the gate and explains failures; the builder fixes; at most 3 rounds.
4. `/polish` — the `polisher` removes stubs, adds tactile feedback, writes `DEMO_READY.md`. Then `/simplify`, then you run `./demo.sh` and look at it.

Before opening a PR: `/code-review medium`. A human merges; agents never do.

## Hard rules (also enforced by `.claude/settings.json`)
- Never push to `main` or `master`, never force-push, never rewrite history.
- Never merge a pull request.
- Never read or write `.env*` files (except `*.example`, `*.sample`, `*.template`), production config or deploy manifests. The deny list blocks the usual names; `smoke.sh` fails on any other `.env*` in the tree.
- Never `rm -rf`, never `pip install` outside the project's own tooling.
- Never skip, delete or weaken a test to get green.
- Use `git -C <dir>`, never `cd` before git.

## Working style
- Plan in plain words before writing code. Small slices; one logical change per commit.
- Stages run one at a time. Never run two agents that write to the tree at the same time.
- The Stop hook runs `scripts/smoke.sh` when `DEMO_SPEC.md` and `demo.sh` exist; it blocks once on failure, then lets go with a message.
- Only the `shaper` has web access.

## Lessons (add a line here whenever Claude gets something wrong)
- A spec step with no observable result cannot be tested; the shaper writes "→ what must be visible".
