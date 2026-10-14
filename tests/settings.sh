#!/usr/bin/env bash
# Asserts the shape of .claude/settings.json (v0.4: single Stop hook, hard deny list).
. "$(dirname "$0")/lib.sh"
S="$ROOT/.claude/settings.json"
py() { "$QS_PYTHON" -c "import json,sys; d=json.load(open(sys.argv[1])); $1" "$S"; }

echo "settings.sh"
expect_exit "valid JSON" 0 "$QS_PYTHON" -m json.tool "$S"
expect_exit "hooks has exactly the key Stop" 0 py "assert list(d['hooks'].keys())==['Stop']"
expect_exit "exactly one Stop entry referencing stop_hook.sh" 0 py \
  "s=d['hooks']['Stop']; assert len(s)==1 and len(s[0]['hooks'])==1 and 'scripts/stop_hook.sh' in s[0]['hooks'][0]['command']"
for k in PreToolUse SubagentStop SessionStart PostToolUse PostToolUseFailure; do
  expect_exit "no $k hook" 0 py "assert '$k' not in d['hooks']"
done
for r in 'Bash(git push *)' 'Bash(gh pr merge *)' 'Read(./.env)' 'Bash(rm -rf*)' 'mcp__github__merge_pull_request' 'Bash(git -C * push*)' 'Read(**/.env*)' 'mcp__github__push_files'; do
  expect_exit "deny contains $r" 0 py "assert '$r' in d['permissions']['deny']"
done
expect_exit "sandbox.enabled is true" 0 py "assert d['sandbox']['enabled'] is True"
finish
