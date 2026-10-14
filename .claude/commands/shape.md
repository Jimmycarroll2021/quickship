---
description: Stage 1 — turn IDEA.md (or the text after the command) into DEMO_SPEC.md
argument-hint: [idea text, if IDEA.md does not exist]
---

Delegate to the `shaper` subagent. Its input is the contents of @IDEA.md and any text after the command: $ARGUMENTS. Its only output is `DEMO_SPEC.md`.

When it returns, show me `DEMO_SPEC.md` in full and stop. I decide whether the spine is right before anything is built. Do not run `/build` on my behalf.
