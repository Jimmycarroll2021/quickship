---
description: Stage 3 — run the live smoke gate and explain every failure; loop builder fixes at most 3 times
---

Delegate to the `verifier` subagent (read-only). It reports PASS (with any coverage gaps) or FAIL.

If it reports FAIL, hand the exact list to the `builder` subagent to fix, then run the verifier again. Do this at most 3 times. If it still fails, stop and show me the last verifier report; do not keep looping and do not weaken any check.

If it reports PASS with coverage gaps, hand the gaps to the builder to add assertions, then verify once more.

Show me the final verifier report verbatim.
