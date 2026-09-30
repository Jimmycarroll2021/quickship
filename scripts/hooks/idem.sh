#!/usr/bin/env bash
# PreToolUse/PostToolUse idempotency guard for Bash: `git push` and `gh pr|issue|release create`.
# Stops the lead from retrying a push/create that already ran to completion for the current step.
# Input: hook JSON on stdin. Fails closed: malformed input -> exit 2. See
# docs/design/contracts.md "Idempotency".
set -u
PY="${QS_PYTHON:-$(command -v python3 || command -v python)}"
in="$(cat)"

parsed="$(printf '%s' "$in" | "$PY" -c '
import json, sys

d = json.load(sys.stdin)
event = d["hook_event_name"]
cmd = d["tool_input"]["command"]

code = 0
if event == "PostToolUse":
    resp = d.get("tool_response")
    if isinstance(resp, dict):
        for k in ("exit_code", "exitCode", "code"):
            v = resp.get(k)
            if isinstance(v, int):
                code = v
                break
    elif isinstance(resp, int):
        code = resp

print(event)
print(str(cmd).replace("\n", " "))
print(code)
' 2>/dev/null)" || { echo "idem: malformed hook input, denied" >&2; exit 2; }
parsed="${parsed//$'\r'/}"   # python on Windows emits CRLF
event="${parsed%%$'\n'*}"; rest="${parsed#*$'\n'}"
cmd="${rest%%$'\n'*}"; code="${rest#*$'\n'}"

# Non-matching commands are a pure no-op: exit before touching the filesystem.
if ! [[ "$cmd" =~ git[[:space:]]+push ]] && ! [[ "$cmd" =~ gh[[:space:]]+(pr|issue|release)[[:space:]]+create ]]; then
  exit 0
fi
case "$event" in PreToolUse|PostToolUse) ;; *) exit 0 ;; esac

S="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.claude/state"
mkdir -p "$S" 2>/dev/null
ledger="$S/idem.jsonl"

key_info="$(IDEM_CMD="$cmd" IDEM_STATE="$S" "$PY" -c '
import hashlib, json, os, re

cmd = os.environ["IDEM_CMD"]
norm = re.sub(r"\s+", " ", cmd).strip()

step = "nostep"
try:
    with open(os.path.join(os.environ["IDEM_STATE"], "current_step.json"), encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and data.get("id"):
        step = str(data["id"])
except (FileNotFoundError, ValueError, OSError):
    pass

key = hashlib.sha256(f"{step}\n{norm}".encode("utf-8")).hexdigest()
print(key)
print(step)
print(norm)
')"
key_info="${key_info//$'\r'/}"
key="${key_info%%$'\n'*}"; rest2="${key_info#*$'\n'}"
step="${rest2%%$'\n'*}"; norm="${rest2#*$'\n'}"

if [ "$event" = PreToolUse ]; then
  done_info="$(IDEM_KEY="$key" IDEM_FILE="$ledger" "$PY" -c '
import json, os

key = os.environ["IDEM_KEY"]
path = os.environ["IDEM_FILE"]
found = ""
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("key") == key and obj.get("status") == "done":
                ts = obj.get("ts", "")
                ex = obj.get("exit", 0)
                found = f"{ts}\t{ex}"
except FileNotFoundError:
    pass
print(found)
')"
  done_info="${done_info//$'\r'/}"
  if [ -n "$done_info" ]; then
    ts="${done_info%%$'\t'*}"; ex="${done_info#*$'\t'}"
    echo "idem: already executed at ${ts} (exit ${ex}); use the recorded result, do not retry" >&2
    exit 2
  fi
  IDEM_KEY="$key" IDEM_STEP="$step" IDEM_CMD="$norm" IDEM_FILE="$ledger" "$PY" -c '
import datetime, json, os

line = {
    "key": os.environ["IDEM_KEY"],
    "step": os.environ["IDEM_STEP"],
    "cmd": os.environ["IDEM_CMD"],
    "status": "pending",
    "exit": 0,
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(os.environ["IDEM_FILE"], "a", encoding="utf-8") as f:
    f.write(json.dumps(line) + "\n")
'
  exit 0
fi

# PostToolUse: record the outcome.
IDEM_KEY="$key" IDEM_STEP="$step" IDEM_CMD="$norm" IDEM_CODE="$code" IDEM_FILE="$ledger" "$PY" -c '
import datetime, json, os

try:
    code = int(os.environ.get("IDEM_CODE", "0"))
except ValueError:
    code = 0

line = {
    "key": os.environ["IDEM_KEY"],
    "step": os.environ["IDEM_STEP"],
    "cmd": os.environ["IDEM_CMD"],
    "status": "done",
    "exit": code,
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(os.environ["IDEM_FILE"], "a", encoding="utf-8") as f:
    f.write(json.dumps(line) + "\n")
'
exit 0
