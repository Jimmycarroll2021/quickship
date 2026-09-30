#!/usr/bin/env bash
# Usage: scripts/validate_brief.sh [brief] [schema]
# Validates a mission brief against its schema with an embedded jq validator.
# Exit 0 + "brief: VALID" on stderr, or exit 2 + one "$.path: message" per line.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BRIEF="${1:-$ROOT/mission/BRIEF.yaml}"
SCHEMA="${2:-$ROOT/mission/BRIEF.schema.yaml}"

for f in "$BRIEF" "$SCHEMA"; do
  [ -f "$f" ] || { echo "\$: file not found: $f" >&2; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
yq -c . "$BRIEF" >"$TMP/brief.json" 2>"$TMP/err" || { echo "\$: cannot parse $BRIEF: $(head -n1 "$TMP/err")" >&2; exit 2; }
yq -c . "$SCHEMA" >"$TMP/schema.json" 2>"$TMP/err" || { echo "\$: cannot parse $SCHEMA: $(head -n1 "$TMP/err")" >&2; exit 2; }
[ -s "$TMP/brief.json" ] && [ -s "$TMP/schema.json" ] || { echo "\$: empty document" >&2; exit 2; }

read -r -d '' PROG <<'JQ'
def istype($t):
  if $t == "integer" then (type == "number" and . == floor)
  elif $t == "number" then type == "number"
  else type == $t end;

def v($s; $p):
  . as $d
  | (if $s.type then
       ([$s.type] | flatten) as $ts
       | if any($ts[]; . as $t | $d | istype($t)) then empty
         else "\($p): expected type \($ts | join("|")), got \($d | type)" end
     else empty end),
    (if ($s | has("const")) and $d != $s.const
     then "\($p): must equal \($s.const | tojson)" else empty end),
    (if ($s | has("enum")) and (any($s.enum[]; . == $d) | not)
     then "\($p): must be one of \($s.enum | tojson)" else empty end),
    (if ($d | type) == "string" then
       (if $s.minLength != null and ($d | length) < $s.minLength
        then "\($p): must have length >= \($s.minLength)" else empty end),
       (if $s.pattern != null and ($d | test($s.pattern) | not)
        then "\($p): does not match pattern \($s.pattern)" else empty end)
     else empty end),
    (if ($d | type) == "number" and $s.minimum != null and $d < $s.minimum
     then "\($p): must be >= \($s.minimum)" else empty end),
    (if ($d | type) == "object" then
       (($s.required // [])[] | select(. as $k | $d | has($k) | not)
        | "\($p): missing required property \(.)"),
       (($s.properties // {}) as $props
        | ($d | keys_unsorted[]) as $k
        | if $props | has($k) then $d[$k] | v($props[$k]; "\($p).\($k)")
          elif $s.additionalProperties == false then "\($p).\($k): unknown property"
          else empty end)
     else empty end),
    (if ($d | type) == "array" then
       (if $s.minItems != null and ($d | length) < $s.minItems
        then "\($p): must have at least \($s.minItems) items" else empty end),
       (if $s.items then range(0; $d | length) as $i | $d[$i] | v($s.items; "\($p)[\($i)]")
        else empty end)
     else empty end),
    (if $s.oneOf then
       $s.oneOf as $vs
       | ([$vs[] | select(($d | type) == "object" and .properties.kind.const != null
                          and .properties.kind.const == $d.kind)]) as $pinned
       | if ($pinned | length) == 1 then $d | v($pinned[0]; $p)
         else ([$vs[] | select(([$d | v(.; $p)] | length) == 0)] | length) as $n
              | if $n == 1 then empty
                else "\($p): matched \($n) of \($vs | length) oneOf variants (expected exactly 1)" end
         end
     else empty end);

$brief | v($schema; "$")
JQ

ERRS="$(jq -rn --slurpfile brief "$TMP/brief.json" --slurpfile schema "$TMP/schema.json" \
  '$brief[0] as $brief | $schema[0] as $schema | '"$PROG" 2>&1)" || { echo "\$: validator error: $ERRS" >&2; exit 2; }

if [ -n "$ERRS" ]; then
  echo "$ERRS" >&2
  exit 2
fi
echo "brief: VALID" >&2
