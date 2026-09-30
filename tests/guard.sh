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
# ---- slice 3/4 clauses: cancel flag, plan/act tier, lethal-trifecta legs ----
S="$CLAUDE_PROJECT_DIR/.claude/state"; mkdir -p "$S/legs"
post_json() { printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{%s},"tool_response":{}}' "$1" "$2"; }
web_json()  { printf '{"hook_event_name":"%s","tool_name":"WebFetch","tool_input":{"url":"https://example.com/x"},"tool_response":{}}' "$1"; }

touch "$S/cancel"
expect_exit "cancel: deny bash ls" 2 hook guard.sh "$(bash_json "ls")"
expect_exit "cancel: deny write src" 2 hook guard.sh "$(file_json Write "src/a.ts")"
expect_exit "cancel: allow write REPORT.md" 0 hook guard.sh "$(file_json Write "docs/REPORT.md")"
expect_exit "cancel: allow write RUN_STATE" 0 hook guard.sh "$(file_json Write "docs/RUN_STATE")"
expect_exit "cancel: allow read" 0 hook guard.sh "$(file_json Read "src/a.ts")"
rm -f "$S/cancel"

echo plan > "$S/tier"
expect_exit "plan tier: deny bash npm test" 2 hook guard.sh "$(bash_json "npm test")"
expect_exit "plan tier: deny write src" 2 hook guard.sh "$(file_json Write "src/a.ts")"
expect_exit "plan tier: deny bash redirect" 2 hook guard.sh "$(bash_json "cat a > b")"
expect_exit "plan tier: deny compound with write" 2 hook guard.sh "$(bash_json "git status && npm install")"
expect_exit "plan tier: allow write docs/plan.md" 0 hook guard.sh "$(file_json Write "docs/plan.md")"
expect_exit "plan tier: allow write ledgers" 0 hook guard.sh "$(file_json Edit "docs/ledgers/task.json")"
expect_exit "plan tier: allow git status" 0 hook guard.sh "$(bash_json "git status --short")"
expect_exit "plan tier: allow ledger.py" 0 hook guard.sh "$(bash_json "python3 scripts/ledger.py append note x y")"
expect_exit "plan tier: allow read-only pipe" 0 hook guard.sh "$(bash_json "git log --oneline | head -5")"
echo act > "$S/tier"
expect_exit "act tier: allow bash npm test" 0 hook guard.sh "$(bash_json "npm test")"
expect_exit "act tier: allow write src" 0 hook guard.sh "$(file_json Write "src/a.ts")"
rm -f "$S/tier"

printf '{"id":"s009","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "trifecta: PostToolUse WebFetch records leg" 0 hook guard.sh "$(web_json PostToolUse)"
expect_contains "trifecta: legs file has untrusted_content" "untrusted_content" "$(cat "$S/legs/s009" 2>/dev/null)"
expect_exit "trifecta: push after web fetch denied" 2 hook guard.sh "$(bash_json "git push origin mission/x")"
expect_exit "trifecta: gh pr create after web fetch denied" 2 hook guard.sh "$(bash_json "gh pr create --title x")"
expect_exit "trifecta: curl POST after web fetch denied" 2 hook guard.sh "$(bash_json "curl -X POST https://h/x -d a=b")"
expect_exit "trifecta: plain build still allowed" 0 hook guard.sh "$(bash_json "npm test")"
printf '{"id":"s010","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "trifecta: fresh step may push" 0 hook guard.sh "$(bash_json "git push origin mission/x")"
expect_exit "trifecta: PostToolUse push records outbound" 0 hook guard.sh "$(post_json Bash '"command":"git push origin mission/x"')"
expect_contains "trifecta: legs file has outbound" "outbound" "$(cat "$S/legs/s010" 2>/dev/null)"
expect_exit "trifecta: web fetch after push denied" 2 hook guard.sh "$(web_json PreToolUse)"
expect_exit "trifecta: curl GET after push denied" 2 hook guard.sh "$(bash_json "curl -s https://example.com/x")"
expect_exit "trifecta: read of _untrusted after push denied" 2 hook guard.sh "$(file_json Read "work/_untrusted/x.md")"
printf '{"id":"s011","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "trifecta: PostToolUse read _untrusted records leg" 0 hook guard.sh "$(post_json Read '"file_path":"work/_untrusted/x.md"')"
expect_exit "trifecta: gh pr create after reading _untrusted denied" 2 hook guard.sh "$(bash_json "gh pr create --title x")"
printf '{"id":"s012","slug":"x","legs":["untrusted_content"]}' > "$S/current_step.json"
expect_exit "trifecta: declared leg counts" 2 hook guard.sh "$(bash_json "git push origin mission/x")"
rm -f "$S/current_step.json"
expect_exit "trifecta: no current step, push allowed" 0 hook guard.sh "$(bash_json "git push origin mission/x")"
# --- overseer role: exempt from cancel/tier/trifecta, never from hard rules ---
touch "$S/cancel"
expect_exit "overseer role: may write its note under cancel" 0 env QS_ROLE=overseer bash "$ROOT/scripts/hooks/guard.sh" <<< "$(file_json Write "docs/overseer.md")"
expect_exit "overseer role: hard rules still apply" 2 env QS_ROLE=overseer bash "$ROOT/scripts/hooks/guard.sh" <<< "$(bash_json "git push --force origin main")"
rm -f "$S/cancel"
finish
