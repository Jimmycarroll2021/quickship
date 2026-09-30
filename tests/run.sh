#!/usr/bin/env bash
# Runs every tests/*.sh (except itself and lib.sh). Exit 0 all green, 2 otherwise. No LLM calls.
cd "$(dirname "$0")/.." || exit 2
echo "tests: claude $(claude --version 2>/dev/null | head -1 || echo unavailable)"
failed=()
for t in tests/*.sh; do
  case "$t" in tests/run.sh|tests/lib.sh) continue;; esac
  echo "== $t"
  bash "$t" || failed+=("$t")
done
if [ ${#failed[@]} -gt 0 ]; then echo "tests: FAIL ${failed[*]}" >&2; exit 2; fi
echo "tests: PASS"
