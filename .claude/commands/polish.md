---
description: Stage 4 — remove half-baked tells, add tactile feedback, write DEMO_READY.md
---

Require a passing `bash scripts/smoke.sh`; if it fails, say so and stop (run `/verify` first). Delegate to the `polisher` subagent.

When it returns, run `/simplify` on the changed code, rerun `bash scripts/smoke.sh`, and show me `DEMO_READY.md` in full plus the gate's last line. Then tell me the one command to open the demo. Do not open a pull request on my behalf; I run `/code-review medium` and decide.
