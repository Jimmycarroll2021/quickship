#!/usr/bin/env bash
# PreToolUse guard: hard rules from CLAUDE.md, enforced by the repo itself (no reliance on ~/.claude).
source "$(dirname "$0")/lib.sh"
export CLAUDE_PROJECT_DIR="$(tmpdir)"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state"
bash_json() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
file_json() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }

for cmd in "git push --force origin main" "git push -f origin main" "git push --force-with-lease origin feat/x" \
           "git push origin main" "git push origin HEAD:main" "git push -u origin master" \
           "git reset --hard HEAD~1" "git branch -D feat/x" "git checkout -- ." \
           "pip install requests" "pip3 install requests" "rm -rf node_modules" "cat .env" "cat ./.env.local"; do
  expect_exit "deny bash: $cmd" 2 hook guard.sh "$(bash_json "$cmd")"
done
for cmd in "git push origin mission/x" "git push -u origin feat/s1-safe-scaffold" "npm test" "cat .env.example" \
           "git checkout -b feat/y" "git branch -d feat/x" "rm -r build"; do
  expect_exit "allow bash: $cmd" 0 hook guard.sh "$(bash_json "$cmd")"
done
for f in ".env" ".env.production" "src/.env.local" "vercel.json" "fly.toml" "infra/main.tf" ".github/workflows/deploy.yml" "Dockerfile.deploy"; do
  expect_exit "deny write: $f" 2 hook guard.sh "$(file_json Write "$f")"
done
expect_exit "deny edit: .env" 2 hook guard.sh "$(file_json Edit ".env")"
expect_exit "deny read: .env" 2 hook guard.sh "$(file_json Read ".env")"
for f in ".env.example" "src/app.ts" "docs/plan.md" ".github/workflows/ci.yml" "Dockerfile"; do
  expect_exit "allow write: $f" 0 hook guard.sh "$(file_json Write "$f")"
done
expect_exit "garbage stdin fails closed" 2 hook guard.sh "not json"
expect_exit "empty stdin fails closed" 2 hook guard.sh ""
expect_exit "missing tool_input fails closed" 2 hook guard.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
hook guard.sh "$(bash_json "npm test")" >/dev/null 2>&1
expect_contains "hook_log records the call" "npm test" "$(cat "$CLAUDE_PROJECT_DIR/.claude/state/hook_log" 2>/dev/null)"
finish
