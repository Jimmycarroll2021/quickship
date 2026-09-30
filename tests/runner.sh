#!/usr/bin/env bash
# tests/runner.sh: verifies tests/run.sh runs test files concurrently with deterministic, filename-ordered
# output, unchanged pass/fail semantics and exit codes, and that QS_TEST_JOBS=1 matches the default.
source "$(dirname "$0")/lib.sh"

mkfixture() { # -> fresh <dir>/tests/ containing the run.sh + lib.sh under test
  local d; d="$(tmpdir)"
  mkdir -p "$d/tests"
  cp "$ROOT/tests/run.sh" "$d/tests/run.sh"
  cp "$ROOT/tests/lib.sh" "$d/tests/lib.sh"
  printf '%s\n' "$d"
}

write_test() { # write_test <dir> <filename> <exit> <line> [sleep-secs]
  cat > "$1/tests/$2" <<EOF
#!/usr/bin/env bash
${5:+sleep $5}
echo "$4"
exit $3
EOF
  chmod +x "$1/tests/$2"
}

# --- mixed pass/fail: exit code, order preserved, both outputs present, final line names the failure ---
for jobs_label in "default:" "QS_TEST_JOBS=1:1"; do
  label="${jobs_label%%:*}"; jobs="${jobs_label#*:}"
  d="$(mkfixture)"
  write_test "$d" aa.sh 0 "aa ok"
  write_test "$d" bb.sh 1 "bb FAIL"
  if [ -n "$jobs" ]; then OUT="$(cd "$d" && QS_TEST_JOBS="$jobs" bash tests/run.sh 2>&1)"; code=$?
  else OUT="$(cd "$d" && bash tests/run.sh 2>&1)"; code=$?; fi
  [ "$code" = 2 ] && ok "$label exit 2" || bad "$label exit 2 (got $code): $(printf '%s' "$OUT" | tail -n 3)"
  aa_line="$(printf '%s\n' "$OUT" | grep -n '^== tests/aa.sh$' | head -1 | cut -d: -f1)"
  bb_line="$(printf '%s\n' "$OUT" | grep -n '^== tests/bb.sh$' | head -1 | cut -d: -f1)"
  if [ -n "$aa_line" ] && [ -n "$bb_line" ] && [ "$aa_line" -lt "$bb_line" ]; then ok "$label aa.sh printed before bb.sh"
  else bad "$label aa.sh printed before bb.sh (aa=$aa_line bb=$bb_line)"; fi
  expect_contains "$label output contains aa.sh's output" "aa ok" "$OUT"
  expect_contains "$label output contains bb.sh's output" "bb FAIL" "$OUT"
  last="$(printf '%s\n' "$OUT" | tail -n 1)"
  expect_contains "$label final line names tests/bb.sh" "tests/bb.sh" "$last"
done

# --- all passing: exit 0, last line is tests: PASS ---
d="$(mkfixture)"
write_test "$d" aa.sh 0 "aa ok"
write_test "$d" cc.sh 0 "cc ok"
expect_exit "all passing: exit 0" 0 bash -c "cd '$d' && bash tests/run.sh"
expect_contains "all passing: last line is tests: PASS" "tests: PASS" "$(printf '%s\n' "$OUT" | tail -n 1)"

# --- real concurrency: two 3s tests run in parallel under QS_TEST_JOBS=2, meaningfully faster than
# running them one at a time (QS_TEST_JOBS=1) measured in the same run, so this holds under machine load too ---
d="$(mkfixture)"
write_test "$d" s1.sh 0 "s1 ok" 3
write_test "$d" s2.sh 0 "s2 ok" 3
start=$(date +%s)
(cd "$d" && QS_TEST_JOBS=1 bash tests/run.sh) >/dev/null 2>&1
serial=$(( $(date +%s) - start ))
start=$(date +%s)
(cd "$d" && QS_TEST_JOBS=2 bash tests/run.sh) >/dev/null 2>&1
parallel=$(( $(date +%s) - start ))
if [ "$parallel" -lt "$serial" ] && [ "$parallel" -lt 6 ]; then
  ok "QS_TEST_JOBS=2 runs two 3s tests concurrently (parallel=${parallel}s < serial=${serial}s)"
else
  bad "QS_TEST_JOBS=2 runs two 3s tests concurrently (parallel=${parallel}s, serial=${serial}s)"
fi

finish
