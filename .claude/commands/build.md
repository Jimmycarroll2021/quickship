---
description: Stage 2 — build the vertical slice in DEMO_SPEC.md, with demo.sh and the smoke spec
---

Require `DEMO_SPEC.md`; if it is missing, say so and stop. Delegate to the `builder` subagent with `DEMO_SPEC.md`, then run `/simplify`.

Afterwards rerun `bash scripts/smoke.sh` and show me its last 20 lines. Do not run `/verify` or `/polish` on my behalf.
