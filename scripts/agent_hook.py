"""Record security-agent evidence independently of the lead."""
import json
import hashlib
import re
import subprocess
import sys
import runtime


def artifacts(brief):
    result = {}
    root = runtime.root()
    for name in brief["mission"]["deliverables"]:
        path = (root / name).resolve()
        if not path.is_relative_to(root) or not path.exists():
            raise ValueError("missing or outside-project review artifact")
        if path.is_file():
            result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            names = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", name],
                                   cwd=root, capture_output=True, check=True).stdout.decode().split("\0")
            contents = {}
            for filename in filter(None, names):
                entry = root / filename
                if not entry.resolve().is_relative_to(root):
                    raise ValueError("review artifact resolves outside project")
                if entry.is_file():
                    contents[filename] = hashlib.sha256(entry.read_bytes()).hexdigest()
            result[name] = hashlib.sha256(json.dumps(contents, sort_keys=True).encode()).hexdigest()
    return result


def handle(event):
    if not runtime.active():
        return 0
    if event.get("hook_event_name") != "SubagentStop":
        return 0
    if event.get("agent_type") == "reviewer":
        brief = runtime.load(runtime.state() / "controller.json")["brief"]
        text = event.get("last_assistant_message", "")
        with runtime.transaction() as db:
            if not runtime.get(db, "agent:" + str(event.get("agent_id"))):
                return 0
            for match in re.finditer(r"^judge\s+(\d+):\s*(PASS|FAIL):\s*(.+)$", text, re.MULTILINE):
                index = int(match[1])
                criteria = brief["success_criteria"]
                judges = [i for i, c in enumerate(criteria) if c["kind"] == "judge"]
                # A sole judge numbered zero is unambiguous, even when a file/test precedes it.
                if index == 0 and len(judges) == 1 and criteria[0]["kind"] != "judge":
                    index = judges[0]
                if index < len(criteria) and criteria[index]["kind"] == "judge":
                    runtime.put(db, "judge:" + str(index), {"verdict": match[2], "evidence": match[3],
                        "rubric": criteria[index]["rubric"], "artifacts": artifacts(brief), "agent_id": event.get("agent_id")})
        return 0
    if event.get("agent_type") == "security":
        text = event.get("last_assistant_message", "")
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=runtime.root(),
                             capture_output=True, text=True, check=True).stdout.strip()
        with runtime.transaction() as db:
            reviewed = runtime.get(db, "agent-head:" + str(event.get("agent_id")))
            runtime.put(db, "security", {"verdict": "PASS" if text.strip().startswith("PASS") and reviewed == sha else "FAIL",
                "evidence": text, "head": sha, "agent_id": event.get("agent_id")})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(handle(json.load(sys.stdin)))
    except (ValueError, KeyError, OSError) as exc:
        print("agent hook: " + str(exc), file=sys.stderr)
        sys.exit(2)
