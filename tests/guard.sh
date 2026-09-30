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
# per-subcommand matching: rules see each subcommand of a compound line, with git -C/--git-dir/--work-tree normalised
for cmd in "git push origin mission/x && gh pr create --base main --title t" "echo main && git push origin mission/x"            'git -C .claude/worktrees/x commit -m \"x\"'; do
  expect_exit "allow compound: $cmd" 0 hook guard.sh "$(bash_json "$cmd")"
done
for cmd in "cd .claude/worktrees/x && git push origin main" "git -C .claude/worktrees/x push --force origin feat/y"            "git -C /tmp/x reset --hard HEAD~1" "ls; git push origin HEAD:main" "true | pip install x"            "git --git-dir=/tmp/x/.git push origin main" "git -C a --work-tree b push -f origin feat/y"; do
  expect_exit "deny compound: $cmd" 2 hook guard.sh "$(bash_json "$cmd")"
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
printf '{"id":"s013","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "trifecta: PostToolUse cd && push records outbound" 0 hook guard.sh "$(post_json Bash '"command":"cd .claude/worktrees/x && git push origin mission/x"')"
expect_contains "trifecta: cd && push is outbound" "outbound" "$(cat "$S/legs/s013" 2>/dev/null)"
printf '{"id":"s014","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "trifecta: PostToolUse git -C push records outbound" 0 hook guard.sh "$(post_json Bash '"command":"git -C .claude/worktrees/x push origin mission/x"')"
expect_contains "trifecta: git -C push is outbound" "outbound" "$(cat "$S/legs/s014" 2>/dev/null)"
rm -f "$S/current_step.json"
expect_exit "trifecta: no current step, push allowed" 0 hook guard.sh "$(bash_json "git push origin mission/x")"
# --- cd before git: Claude Code's permission layer auto-denies it in a headless run, so the guard denies it first
# with an actionable reason (use git -C). A cd before a non-git command, and git -C itself, stay allowed. ---
for cmd in "cd .claude/worktrees/x && git add -A && git commit -m x" "cd /tmp/x && git status --short" "cd x; git log -1"; do
  expect_exit "cd-then-git denied: $cmd" 2 hook guard.sh "$(bash_json "$cmd")"
  expect_contains "cd-then-git reason names git -C: $cmd" "git -C" "$OUT"
done
for cmd in "cd .claude/worktrees/x && bash scripts/gate.sh" "git -C .claude/worktrees/x add -A && git -C .claude/worktrees/x commit -m x" "cd x && python scripts/ledger.py tier act"; do
  expect_exit "cd without git allowed: $cmd" 0 hook guard.sh "$(bash_json "$cmd")"
done
# --- overseer role: exempt from cancel/tier/trifecta, never from hard rules ---
touch "$S/cancel"
expect_exit "overseer role: may write its note under cancel" 0 env QS_ROLE=overseer bash "$ROOT/scripts/hooks/guard.sh" <<< "$(file_json Write "docs/overseer.md")"
expect_exit "overseer role: hard rules still apply" 2 env QS_ROLE=overseer bash "$ROOT/scripts/hooks/guard.sh" <<< "$(bash_json "git push --force origin main")"
rm -f "$S/cancel"
# ---- Windows paths: the Write/Edit/Read tools pass backslash paths; every file rule must see them as slashes ----
# Fixtures are built with json.dumps so the backslashes are valid JSON escapes, exactly as Claude Code sends them.
file_json_py() { "$QS_PYTHON" -c 'import json,sys; print(json.dumps({"hook_event_name":sys.argv[3],"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]},"tool_response":{}}))' "$1" "$2" "${3:-PreToolUse}"; }
OUT="$(printf '%s' "$(file_json_py Write 'C:\repo\x')" | "$QS_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["tool_input"]["file_path"])')"
expect_contains "backslash: fixture is valid json carrying a backslash path" 'C:\repo\x' "$OUT"
expect_exit "backslash: deny write .env" 2 hook guard.sh "$(file_json_py Write 'C:\repo\.env')"
expect_exit "backslash: deny write vercel.json" 2 hook guard.sh "$(file_json_py Write 'C:\repo\vercel.json')"
expect_exit "backslash: deny edit infra" 2 hook guard.sh "$(file_json_py Edit 'C:\repo\infra\main.tf')"
expect_exit "backslash: allow write src" 0 hook guard.sh "$(file_json_py Write 'C:\repo\src\a.ts')"
echo plan > "$S/tier"
expect_exit "backslash: plan tier allows docs\plan.md" 0 hook guard.sh "$(file_json_py Write 'C:\repo\docs\plan.md')"
expect_exit "backslash: plan tier denies src\a.ts" 2 hook guard.sh "$(file_json_py Write 'C:\repo\src\a.ts')"
rm -f "$S/tier"; touch "$S/cancel"
expect_exit "backslash: cancel allows docs\REPORT.md" 0 hook guard.sh "$(file_json_py Write 'C:\repo\docs\REPORT.md')"
rm -f "$S/cancel"
printf '{"id":"s020","slug":"x","legs":[]}' > "$S/current_step.json"
expect_exit "backslash: PostToolUse read of work\_untrusted records leg" 0 hook guard.sh "$(file_json_py Read 'C:\repo\work\_untrusted\x.md' PostToolUse)"
expect_contains "backslash: legs file has untrusted_content" "untrusted_content" "$(cat "$S/legs/s020" 2>/dev/null)"
rm -f "$S/current_step.json"
finish
