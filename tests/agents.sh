#!/usr/bin/env bash
# Agent prompts carry the shell discipline that keeps headless runs out of Claude Code's permission prompts:
# proof mission 4 lost ten minutes to compound commands, exit-code echoes, redirects into /tmp and absolute
# script paths, none of which match the relative allow rules passed via --allowedTools.
source "$(dirname "$0")/lib.sh"
for a in worker reviewer security; do
  P="$(cat "$ROOT/.claude/agents/$a.md")"
  expect_contains "$a: one command per Bash call" "One command per Bash call" "$P"
  expect_contains "$a: relative paths" "relative" "$P"
  expect_contains "$a: no redirects outside the repo" "/tmp" "$P"
  expect_contains "$a: no exit-code echoes" "PIPESTATUS" "$P"
done
# QA: the security reviewer is read-only by frontmatter; workers ship tests with behaviour; the reviewer fails code without one.
S_MD="$ROOT/.claude/agents/security.md"
if [ -f "$S_MD" ]; then ok "security.md exists"; else bad "security.md exists"; fi
expect_contains "security: disallows Write and Edit" "disallowedTools: Write, Edit" "$(grep '^disallowedTools:' "$S_MD" 2>/dev/null)"
expect_contains "worker: test that fails without it" "test that fails without it" "$(cat "$ROOT/.claude/agents/worker.md")"
expect_contains "reviewer: behaviour change without a test fails" "without a test" "$(cat "$ROOT/.claude/agents/reviewer.md")"
expect_contains "lead loop carries the same rule" "One command per Bash call" "$(cat "$ROOT/CLAUDE.md")"
finish
