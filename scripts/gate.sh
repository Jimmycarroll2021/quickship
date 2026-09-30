#!/usr/bin/env bash
# Quality gate: secrets scan, lint, test, build.
# Exit 0 = pass, exit 2 = fail (failures on stderr). Used by the Stop hook.
# If mission/BRIEF.yaml exists, also validates the brief, enforces the step
# budget, evaluates the success criteria and writes mission/REPORT.md whose
# line 1 is the termination state: DONE | DONE_PARTIAL | SAFE_STOP (exit 0) or HALT (exit 2).
# Stack is detected at run time from manifests/lockfiles in the repo root.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "gate: cannot cd to $ROOT" >&2; exit 2; }

failures=()
results=()
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run() { # run <label> <cmd...>
  local label="$1"; shift
  echo "gate: $label -> $*" >&2
  if ! "$@" >"$log" 2>&1; then
    failures+=("$label failed: $*")
    results+=("$label: FAIL")
    tail -n 40 "$log" >&2
  else
    results+=("$label: PASS")
  fi
}

# --- secrets: tracked .env files and common key formats in tracked files ---
if git rev-parse --git-dir >/dev/null 2>&1; then
  envfiles="$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -vE '\.(example|sample|template)$' || true)"
  secrets_before=${#failures[@]}
  [ -n "$envfiles" ] && failures+=("secrets: tracked env file(s): $envfiles")
  pattern='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  hits="$(git ls-files -z | xargs -0 -r grep -IlE "$pattern" 2>/dev/null || true)"
  [ -n "$hits" ] && failures+=("secrets: possible credential in: $hits")
  if [ ${#failures[@]} -gt "$secrets_before" ]; then results+=("secrets: FAIL"); else results+=("secrets: PASS"); fi
else
  results+=("secrets: SKIPPED (not a git repo)")
fi

# --- stack detection ---
has_script() { node -e "process.exit(require('./package.json').scripts?.['$1']?0:1)" 2>/dev/null; }

if [ -f package.json ]; then
  if   [ -f pnpm-lock.yaml ]; then pm=pnpm
  elif [ -f yarn.lock ];      then pm=yarn
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
  else pm=npm; fi
  echo "gate: detected node ($pm)" >&2
  [ -d node_modules ] || run install "$pm" install
  for s in lint test build; do
    if has_script "$s"; then run "$s" "$pm" run "$s"
    else echo "gate: WARNING no '$s' script in package.json, skipped" >&2; results+=("$s: SKIPPED (no script)"); fi
  done
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  if [ -f uv.lock ]; then py="uv run"; else py=""; fi
  echo "gate: detected python${py:+ (uv)}" >&2
  if $py ruff --version >/dev/null 2>&1; then run lint $py ruff check .
  else echo "gate: WARNING ruff not available, lint skipped" >&2; results+=("lint: SKIPPED (ruff not available)"); fi
  if ls tests test 2>/dev/null | grep -q . || compgen -G "**/test_*.py" >/dev/null; then
    run test $py pytest -q
  else echo "gate: WARNING no tests found, skipped" >&2; results+=("test: SKIPPED (no tests found)"); fi
  if [ -f pyproject.toml ] && grep -q '^\[build-system\]' pyproject.toml; then
    if [ -n "$py" ]; then run build uv build; else run build python -m build; fi
  fi
else
  echo "gate: WARNING no stack detected (no package.json/pyproject.toml/requirements.txt); only secrets scan ran" >&2
  results+=("stack: SKIPPED (none detected)")
fi

# --- mission: brief, step budget, success criteria, REPORT.md ---
BRIEF=mission/BRIEF.yaml
PROGRESS=mission/ledgers/progress.jsonl
TASK=mission/ledgers/task.json
state=""
rows=()

cell() { printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\\|/g'; } # table-safe text

# eval_criterion <json> -> sets c_result and c_detail
eval_criterion() {
  local c="$1" id kind cmd t path assert rubric ext out verdict
  id="$(jq -r '.id' <<<"$c")"; kind="$(jq -r '.kind' <<<"$c")"
  c_result=FAIL; c_detail=""
  case "$kind" in
    test)
      cmd="$(jq -r '.cmd' <<<"$c")"; t="$(jq -r '.timeout_s // 300' <<<"$c")"
      echo "gate: criterion $id -> $cmd" >&2
      timeout "$t" bash -c "$cmd" </dev/null >"$log" 2>&1; rc=$?
      if [ $rc -eq 0 ]; then c_result=PASS; c_detail="exit 0"
      elif [ $rc -eq 124 ]; then c_detail="timed out after ${t}s"; tail -n 40 "$log" >&2
      else c_detail="exit $rc"; tail -n 40 "$log" >&2; fi ;;
    file)
      path="$(jq -r '.path' <<<"$c")"; assert="$(jq -r '.assert // empty' <<<"$c")"
      if [ ! -e "$path" ]; then c_detail="missing: $path"
      elif [ -z "$assert" ]; then c_result=PASS; c_detail="exists: $path"
      else
        ext="${path##*.}"
        case "$ext" in
          yaml|yml) out="$(yq -c . "$path" 2>/dev/null | jq -c "$assert" 2>&1)" ;;
          json)     out="$(jq -c . "$path" 2>/dev/null | jq -c "$assert" 2>&1)" ;;
          *)        out=""; c_detail="assert unsupported for .$ext" ;;
        esac
        if [ -n "$c_detail" ]; then :
        elif [ "$out" = true ]; then c_result=PASS; c_detail="assert true"
        else c_detail="assert gave: ${out:-nothing}"; fi
      fi ;;
    judge)
      verdict="$(head -n 1 "mission/.judge/$id.verdict" 2>/dev/null | tr -d '[:space:]')"
      case "$verdict" in
        PASS) c_result=PASS; c_detail="verdict file" ;;
        FAIL) c_detail="verdict file" ;;
        *)
          rubric="$(jq -r '.rubric' <<<"$c")"
          mkdir -p mission/.judge && printf '%s\n' "$rubric" >"mission/.judge/$id.pending"
          c_result=PENDING_JUDGE; c_detail="awaiting mission/.judge/$id.verdict" ;;
      esac ;;
    *) c_detail="unknown kind: $kind" ;;
  esac
}

if [ -f "$BRIEF" ]; then
  goal="$(yq -r '.goal // ""' "$BRIEF" 2>/dev/null)"
  budget="$(yq -r '.budgets.steps // 0' "$BRIEF" 2>/dev/null)"
  case "$budget" in ''|*[!0-9]*) budget=0 ;; esac
  steps=0; blocked=""
  if [ -f "$PROGRESS" ]; then
    steps="$(jq -Rn '[inputs | fromjson? | select(type=="object" and .type=="STEP")] | length' "$PROGRESS" 2>/dev/null || echo 0)"
    blocked="$(jq -Rr 'fromjson? | select(type=="object" and .type=="STEP" and .status=="blocked") | "- step \(.step): \(.action): \(.detail)"' "$PROGRESS" 2>/dev/null || true)"
  fi
  assumptions=""
  [ -f "$TASK" ] && assumptions="$(jq -r '.entries[]? | select(.type=="ASSUMPTION") | "- step \(.step): \(.summary) -> \(.detail)"' "$TASK" 2>/dev/null || true)"

  echo "gate: validating $BRIEF" >&2
  if bash scripts/validate_brief.sh >"$log" 2>&1; then
    results+=("brief: PASS")
    if [ "$steps" -gt "$budget" ]; then
      state=SAFE_STOP
      results+=("budget: FAIL ($steps steps > $budget)")
    else
      results+=("budget: PASS ($steps / $budget steps)")
      pending=0; cfail=0
      while IFS= read -r -u 3 c; do
        eval_criterion "$c"
        id="$(jq -r '.id' <<<"$c")"; kind="$(jq -r '.kind' <<<"$c")"
        rows+=("| $(cell "$id") | $kind | $c_result | $(cell "$c_detail") |")
        case "$c_result" in
          FAIL) cfail=$((cfail+1)); failures+=("criterion $id failed: $c_detail") ;;
          PENDING_JUDGE) pending=$((pending+1)) ;;
        esac
      done 3< <(yq -c '.success_criteria[]' "$BRIEF")
      if [ ${#failures[@]} -gt 0 ]; then state=HALT
      elif [ "$pending" -gt 0 ]; then state=DONE_PARTIAL
      else state=DONE; fi
    fi
  else
    cat "$log" >&2
    results+=("brief: FAIL")
    failures+=("brief invalid: scripts/validate_brief.sh failed")
    state=HALT
  fi

  {
    echo "$state"
    echo
    echo "# Mission report"
    echo
    echo "Goal: ${goal:-unknown}"
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Steps: $steps / $budget"
    echo
    echo "## Assumptions"
    echo
    echo "${assumptions:-None logged.}"
    echo
    echo "## Blocked steps"
    echo
    echo "${blocked:-None.}"
    echo
    echo "## Gate results"
    echo
    for r in "${results[@]}"; do echo "- $r"; done
    echo
    echo "## Success criteria"
    echo
    echo "| id | kind | result | detail |"
    echo "|---|---|---|---|"
    if [ ${#rows[@]} -gt 0 ]; then printf '%s\n' "${rows[@]}"; fi
  } >mission/REPORT.md
  echo "gate: mission state $state (mission/REPORT.md)" >&2
fi

if [ ${#failures[@]} -gt 0 ]; then
  echo "gate: FAIL" >&2
  i=1; for f in "${failures[@]}"; do echo "  $i. $f" >&2; i=$((i+1)); done
  [ "$state" = SAFE_STOP ] && exit 0
  exit 2
fi
echo "gate: PASS" >&2
exit 0
