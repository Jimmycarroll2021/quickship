#!/usr/bin/env bash
# Runs every tests/*.sh (except itself and lib.sh) concurrently, up to QS_TEST_JOBS at a time
# (default: 1 on Windows; at most 4 elsewhere). Each test's combined output is captured and printed
# in filename order once all tests finish, so output stays deterministic. Exit 0 all green, 2 otherwise.
cd "$(dirname "$0")/.." || exit 2

if [ "${QS_TEST_JOBS+x}" = x ]; then
  jobs="$QS_TEST_JOBS"
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) jobs=1;;
    *) jobs="$(nproc 2>/dev/null || echo 4)"
       [ "$jobs" -le 4 ] 2>/dev/null || jobs=4;;
  esac
fi
if ! [[ "$jobs" =~ ^[1-9][0-9]{0,3}$ ]] || [ "$jobs" -gt 1024 ]; then
  echo "tests: QS_TEST_JOBS must be an integer from 1 to 1024" >&2
  exit 2
fi
v="$(claude --version 2>/dev/null | head -1)"; echo "tests: claude ${v:-unavailable}"

files=()
for t in tests/*.sh; do
  case "$t" in tests/run.sh|tests/lib.sh) continue;; esac
  files+=("$t")
done

retain=0
if [ -n "${QS_TEST_LOG_DIR:-}" ]; then
  mkdir -p "$QS_TEST_LOG_DIR" || exit 2
  logs="$(cd "$QS_TEST_LOG_DIR" && pwd -P)" || exit 2
  workdir="$(mktemp -d "$logs/run.XXXXXXXXXX")" || exit 2
  retain=1
  printf '%s\n' "$jobs" > "$workdir/jobs"
  echo "tests: retained logs $workdir" >&2
else
  workdir="$(mktemp -d)" || exit 2
fi
trap 'if [ "$retain" = 0 ]; then rm -rf "$workdir"; fi' EXIT

running=0
for t in "${files[@]}"; do
  out="$workdir/${t##*/}.out"
  rc="$workdir/${t##*/}.rc"
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
  cat "$workdir/${t##*/}.out"
  [ "$(cat "$workdir/${t##*/}.rc")" = 0 ] || failed+=("$t")
done

if [ ${#failed[@]} -gt 0 ]; then
  # On GitHub Actions, surface failing lines as annotations (readable via the checks API when logs are not).
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    for t in "${failed[@]}"; do
      grep -E '^[[:space:]]*FAIL |^[a-z_]+\.sh: [0-9]+ passed' "$workdir/${t##*/}.out" | head -n 8 \
        | while IFS= read -r l; do printf '::error file=%s::%s\n' "$t" "$l"; done
    done
  fi
  echo "tests: FAIL ${failed[*]}" >&2; exit 2
fi
echo "tests: PASS"
