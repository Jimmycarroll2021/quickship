#!/usr/bin/env bash
# Quality gate: secrets scan, lint, test, build.
# Exit 0 = pass, exit 2 = fail (failures on stderr). Used by the Stop hook.
# Stack is detected at run time from manifests/lockfiles in the repo root.
set -uo pipefail
shopt -s globstar

# Root is the tree we are IN (a git worktree has its own toplevel). CLAUDE_PROJECT_DIR always points at the
# main checkout even inside a worktree, so it is only a fallback.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "gate: cannot cd to $ROOT" >&2; exit 2; }

failures=()
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run() { # run <label> <cmd...>
  local label="$1"; shift
  echo "gate: $label -> $*" >&2
  if ! "$@" >"$log" 2>&1; then
    failures+=("$label failed: $*")
    tail -n 40 "$log" >&2
  fi
}

# --- secrets: tracked .env files and common key formats in tracked AND untracked (not ignored) files ---
if git rev-parse --git-dir >/dev/null 2>&1; then
  envfiles="$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -vE '\.(example|sample|template)$' || true)"
  [ -n "$envfiles" ] && failures+=("secrets: tracked env file(s): $envfiles")
  pattern='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|sk-(ant-|proj-)[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  hits="$(git ls-files -z --cached --others --exclude-standard | xargs -0 -r grep -IlE "$pattern" 2>/dev/null || true)"
  [ -n "$hits" ] && failures+=("secrets: possible credential in: $hits")
fi

# --- stack detection ---
has_script() {
  if command -v node >/dev/null 2>&1; then node -e "process.exit(require('./package.json').scripts?.['$1']?0:1)" 2>/dev/null
  else grep -Eq "\"$1\"[[:space:]]*:" package.json; fi
}

if [ -f package.json ]; then
  if   [ -f pnpm-lock.yaml ]; then pm=pnpm
  elif [ -f yarn.lock ];      then pm=yarn
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
  else pm=npm; fi
  echo "gate: detected node ($pm)" >&2
  [ -d node_modules ] || run install "$pm" install
  for s in lint test build; do
    if has_script "$s"; then run "$s" "$pm" run "$s"
    else echo "gate: WARNING no '$s' script in package.json, skipped" >&2; fi
  done
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  if [ -f uv.lock ]; then py="uv run"; else py=""; fi
  echo "gate: detected python${py:+ (uv)}" >&2
  if $py ruff --version >/dev/null 2>&1; then run lint $py ruff check .
  else echo "gate: WARNING ruff not available, lint skipped" >&2; fi
  if ls tests test 2>/dev/null | grep -q . || compgen -G "**/test_*.py" >/dev/null; then
    run test $py pytest -q
  else echo "gate: WARNING no tests found, skipped" >&2; fi
  if [ -f pyproject.toml ] && grep -q '^\[build-system\]' pyproject.toml; then
    if [ -n "$py" ]; then run build uv build; else run build python -m build; fi
  fi
else
  echo "gate: WARNING no stack detected (no package.json/pyproject.toml/requirements.txt); only secrets scan ran" >&2
fi

# --- harness self-tests (no LLM calls): run in the quickship repo itself. An installed copy (.quickship/VERSION
# present) skips them: they take minutes, test the harness rather than the project, and a lead and a worker running
# them at once can push one past the gate timeout. QS_SELFTEST=1 forces them. ---
if [ -f tests/run.sh ]; then
  if [ -f .quickship/VERSION ] && [ "${QS_SELFTEST:-0}" != 1 ]; then
    echo "gate: harness self-tests skipped in an installed copy (QS_SELFTEST=1 runs them)" >&2
  else
    run tests bash tests/run.sh
  fi
fi

if [ ${#failures[@]} -gt 0 ]; then
  echo "gate: FAIL" >&2
  i=1; for f in "${failures[@]}"; do echo "  $i. $f" >&2; i=$((i+1)); done
  exit 2
fi
echo "gate: PASS" >&2
exit 0
