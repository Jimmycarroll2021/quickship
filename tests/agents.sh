#!/usr/bin/env bash
# Agent prompts carry the shell discipline that keeps headless runs out of Claude Code's permission prompts:
# proof mission 4 lost ten minutes to compound commands, exit-code echoes, redirects into /tmp and absolute
# script paths, none of which match the relative allow rules passed via --allowedTools.
source "$(dirname "$0")/lib.sh"
for a in worker reviewer; do
  P="$(cat "$ROOT/.claude/agents/$a.md")"
  expect_contains "$a: one command per Bash call" "One command per Bash call" "$P"
  expect_contains "$a: relative paths" "relative" "$P"
  expect_contains "$a: no redirects outside the repo" "/tmp" "$P"
  expect_contains "$a: no exit-code echoes" "PIPESTATUS" "$P"
done
expect_contains "lead loop carries the same rule" "One command per Bash call" "$(cat "$ROOT/CLAUDE.md")"
finish
