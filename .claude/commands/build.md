---
description: Stage 2 — build the vertical slice in DEMO_SPEC.md, with demo.sh and the smoke spec
---

Require `DEMO_SPEC.md`; if it is missing, say so and stop. Delegate to the `builder` subagent with the spec and these instructions: build the golden path end to end, create `./demo.sh`, serve the health path, write the smoke spec skeleton, and run `bash scripts/smoke.sh` before returning.

When it returns, run `/simplify` on the changed code, then rerun `bash scripts/smoke.sh` and show me its last 20 lines. Do not run `/verify` or `/polish` on my behalf.
