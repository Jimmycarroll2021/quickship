#!/usr/bin/env bash
# Static checks on the v0.4 agent and command definitions. No model calls.
. "$(dirname "$0")/lib.sh"

AG="$ROOT/.claude/agents"
CM="$ROOT/.claude/commands"

# frontmatter field extractor: fm <file> <key>
fm() { awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} index($0,k":")==1{sub("^"k":[[:space:]]*","");print;exit}' "$1"; }

for a in shaper builder verifier polisher; do
  f="$AG/$a.md"
  [ -f "$f" ] && ok "agent $a exists" || { bad "agent $a missing"; continue; }
  [ "$(fm "$f" name)" = "$a" ] && ok "agent $a: name matches filename" || bad "agent $a: name '$(fm "$f" name)' != filename"
  [ -n "$(fm "$f" description)" ] && ok "agent $a: has description" || bad "agent $a: no description"
  case "$(fm "$f" model)" in opus|sonnet|haiku) ok "agent $a: model is an alias";; *) bad "agent $a: model '$(fm "$f" model)' is not an alias";; esac
done

# only the shaper has web access
for a in builder verifier polisher; do
  case "$(fm "$AG/$a.md" tools)" in *WebSearch*|*WebFetch*) bad "agent $a: has web tools";; *) ok "agent $a: no web tools";; esac
done
case "$(fm "$AG/shaper.md" tools)" in *WebSearch*) ok "shaper: has WebSearch";; *) bad "shaper: missing WebSearch";; esac

# verifier is read-only
v="$(fm "$AG/verifier.md" tools)"
case "$v" in *Write*|*Edit*) bad "verifier: has write tools ($v)";; *) ok "verifier: read-only tool list";; esac
case "$(fm "$AG/verifier.md" disallowedTools)" in *Write*) ok "verifier: Write disallowed";; *) bad "verifier: Write not disallowed";; esac
grep -q "never declare.*PASS\|only thing.*says PASS" "$AG/verifier.md" && ok "verifier: does not declare PASS" || bad "verifier: missing no-PASS rule"

# builder owns the smoke spec; shaper never writes code
grep -q "tests/smoke.spec.ts" "$AG/builder.md" && ok "builder: names the smoke spec" || bad "builder: no smoke spec instruction"
grep -q "no application code" "$AG/shaper.md" && ok "shaper: writes no code" || bad "shaper: missing no-code rule"

# no v0.3 ledger machinery leaks into v0.4 prompts
for f in "$AG"/*.md "$CM"/*.md "$ROOT/CLAUDE.md"; do
  if grep -qE "ledger\.py|step-bind|RUN_STATE|COMPLETION\.json|BRIEF\.yaml|check_criteria" "$f"; then bad "$(basename "$f"): references v0.3 machinery"; else ok "$(basename "$f"): no v0.3 machinery"; fi
done

# commands exist and have a description
for c in shape build verify polish; do
  f="$CM/$c.md"
  [ -f "$f" ] && ok "command /$c exists" || { bad "command /$c missing"; continue; }
  [ -n "$(fm "$f" description)" ] && ok "command /$c: has description" || bad "command /$c: no description"
done
grep -q '@IDEA.md' "$CM/shape.md" && ok "/shape reads IDEA.md" || bad "/shape does not read IDEA.md"
grep -q 'at most 3' "$CM/verify.md" && ok "/verify bounds the fix loop" || bad "/verify has no loop bound"
grep -q '/simplify' "$CM/build.md" && grep -q '/simplify' "$CM/polish.md" && ok "/build and /polish run /simplify" || bad "simplify step missing"
grep -q '/code-review' "$ROOT/CLAUDE.md" && ok "CLAUDE.md: code-review before PR" || bad "CLAUDE.md: no code-review step"
grep -q 'smoke.sh' "$ROOT/CLAUDE.md" && ok "CLAUDE.md: names the gate" || bad "CLAUDE.md: gate not named"
[ "$(wc -l < "$ROOT/CLAUDE.md")" -le 60 ] && ok "CLAUDE.md: 60 lines or fewer" || bad "CLAUDE.md: too long ($(wc -l < "$ROOT/CLAUDE.md") lines)"

finish
