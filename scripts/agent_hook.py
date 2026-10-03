"""Record security-agent evidence independently of the lead."""
import json
import subprocess
import sys
import runtime


def handle(event):
    if not runtime.active():
        return 0
    if event.get("hook_event_name") == "SubagentStop" and event.get("agent_type") == "security":
        text = event.get("last_assistant_message", "")
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=runtime.root(),
                             capture_output=True, text=True, check=True).stdout.strip()
        with runtime.transaction() as db:
            runtime.put(db, "security", {"verdict": "PASS" if text.strip().startswith("PASS") else "FAIL",
                "evidence": text, "head": sha, "agent_id": event.get("agent_id")})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(handle(json.load(sys.stdin)))
    except (ValueError, KeyError, OSError) as exc:
        print("agent hook: " + str(exc), file=sys.stderr)
        sys.exit(2)
