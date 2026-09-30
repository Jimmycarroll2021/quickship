#!/usr/bin/env bash
# Runs every tests/*.sh (except itself and lib.sh) concurrently, up to QS_TEST_JOBS at a time
# (default: nproc, else 4). Each test's combined output is captured to a temp file and printed
# in filename order once all tests finish, so output stays deterministic. Exit 0 all green, 2 otherwise.
cd "$(dirname "$0")/.." || exit 2
echo "tests: claude $(claude --version 2>/dev/null | head -1 || echo unavailable)"

jobs="${QS_TEST_JOBS:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"

files=()
for t in tests/*.sh; do
  case "$t" in tests/run.sh|tests/lib.sh) continue;; esac
  files+=("$t")
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

running=0
for t in "${files[@]}"; do
  out="$workdir/$(basename "$t").out"
  rc="$workdir/$(basename "$t").rc"
  (
    bash "$t" >"$out" 2>&1
    echo $? >"$rc"
  ) &
  running=$((running + 1))
  if [ "$running" -ge "$jobs" ]; then wait -n; running=$((running - 1)); fi
done
wait

failed=()
for t in "${files[@]}"; do
  echo "== $t"
  cat "$workdir/$(basename "$t").out"
  [ "$(cat "$workdir/$(basename "$t").rc")" = 0 ] || failed+=("$t")
done

if [ ${#failed[@]} -gt 0 ]; then echo "tests: FAIL ${failed[*]}" >&2; exit 2; fi
echo "tests: PASS"
