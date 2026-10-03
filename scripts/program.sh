#!/usr/bin/env bash
# Run a chain of mission briefs in order, unattended: docs/missions/NN-*.yaml, as written by scripts/idea.sh.
# Each mission starts from the previous mission's branch and opens its PR against it (mission.base), so the PRs form
# a stack you review and merge at the end, first one first. quickship itself never merges.
# Stops at the first mission that does not end DONE. Re-run to resume: missions already DONE are skipped.
# Usage: bash scripts/program.sh [missions-dir]
# Exit: 0 all DONE, 2 no missions or a brief is invalid, 3 stopped at a mission that did not end DONE.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2
export CLAUDE_PROJECT_DIR="$PWD"
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
RUN="${QS_RUN:-scripts/run.sh}"
dir="${1:-docs/missions}"
S=.claude/state; mkdir -p "$S" docs
LOG="$S/program.tsv"   # mission file <TAB> state <TAB> branch, one line per finished mission
SUMMARY=docs/PROGRAM.md

shopt -s nullglob; missions=("$dir"/[0-9][0-9]-*.yaml); shopt -u nullglob
[ ${#missions[@]} -gt 0 ] || { echo "program: no mission briefs in $dir (write them, or run scripts/idea.sh)" >&2; exit 2; }
"$PY" scripts/brief.py check "${missions[@]}" >/dev/null || { echo "program: fix the mission briefs above first" >&2; exit 2; }
touch "$LOG"
[ -f "$SUMMARY" ] || printf '# Program\n\n| Mission | State | Branch | PR |\n|---|---|---|---|\n' > "$SUMMARY"

state_of() { sed -n 's/.*"state": *"\([A-Z_]*\)".*/\1/p' docs/RUN_STATE 2>/dev/null | head -n 1; }
base=""
for m in "${missions[@]}"; do
  prev="$(awk -F'\t' -v f="$m" '$1 == f && $2 == "DONE"' "$LOG" | tail -n 1)"
  if [ -n "$prev" ]; then base="$(printf '%s' "$prev" | cut -f3)"; echo "program: $m already DONE on $base"; continue; fi
  echo "program: starting $m${base:+ on top of $base}"

  # detached at the base, so the brief commit lands on the new mission's branch and never on main or the base branch
  git checkout -q --detach "${base:-HEAD}" || { echo "program: cannot check out ${base:-HEAD}" >&2; exit 3; }
  if [ -n "$base" ]; then
    awk -v b="$base" '{print} /^  goal:/ && !d {print "  base: \"" b "\""; d=1}' "$m" > BRIEF.yaml
  else
    cp "$m" BRIEF.yaml
  fi
  git add BRIEF.yaml && { git commit -q -m "brief: $(basename "$m" .yaml)" -- BRIEF.yaml >/dev/null 2>&1 || true; }

  st=""
  for _ in 1 2 3 4 5 6; do        # run.sh resumes the same session after a crash; it gives up itself after 5 restarts
    bash "$RUN"; rc=$?
    [ "$rc" = 2 ] && { st=""; break; }   # brief rejected before the last mission's state was archived
    st="$(state_of)"; [ -n "$st" ] && break
  done
  branch="$(git branch --show-current)"
  pr="$(grep -Eo 'https://github\.com/[^ )"`]+/pull/[0-9]+' docs/REPORT.md 2>/dev/null | head -n 1)"
  printf '%s\t%s\t%s\n' "$m" "${st:-NONE}" "$branch" >> "$LOG"
  printf '| %s | %s | %s | %s |\n' "$(basename "$m")" "${st:-NONE}" "${branch:-?}" "${pr:-none}" >> "$SUMMARY"
  if [ "$st" != DONE ]; then
    echo "program: $m ended ${st:-without a terminal state}; read docs/REPORT.md. Later missions were not started." >&2
    exit 3
  fi
  [ -n "$branch" ] || { echo "program: $m ended DONE but not on a branch; cannot chain the next mission" >&2; exit 3; }
  base="$branch"
done
echo "program: all ${#missions[@]} missions DONE. Review and merge the PR stack in order, first mission first. Summary: $SUMMARY"
