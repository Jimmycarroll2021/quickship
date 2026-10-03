"""Read-only readiness diagnostics; no model calls or account changes."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import runtime
import quality
from brief import BriefError, load_yaml, validate_structure


def command(args, cwd):
    # Windows npm/Claude shims are .cmd; Git Bash provides portable resolution.
    if os.name == "nt" and args[0] == "claude":
        import shlex
        args = [quality.bash(), "-c", shlex.join(args)]
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=30)
    if p.returncode:
        raise ValueError(args[0] + " failed: " + p.stderr[-500:])
    return p.stdout


def inspect(root):
    root = Path(root).resolve()
    errors = []
    data = {"python": sys.version.split()[0], "errors": errors}
    if sys.version_info < (3, 10):
        errors.append("Python 3.10+ required")
    for exe in ("git", "gh", "claude"):
        if not shutil.which(exe):
            errors.append(exe + " is missing")
    try:
        version = command([quality.bash(), "--version"], root).splitlines()[0]
        if not re.search(r"version ([4-9]|[1-9][0-9])\.", version):
            errors.append("bash 4+ required")
        data["bash"] = version
        command(["git", "rev-parse", "--show-toplevel"], root)
        auth = json.loads(command(["claude", "auth", "status"], root))
        data["auth"] = {k: auth.get(k) for k in ("loggedIn", "authMethod", "subscriptionType")}
        if not auth.get("loggedIn"):
            errors.append("Claude is not logged in")
        version = command(["claude", "--version"], root).strip()
        data["claude"] = version
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", version)
        if not match or tuple(map(int, match.groups())) < (2, 1, 288):
            errors.append("Claude Code >=2.1.288 required")
        help_text = command(["claude", "--help"], root)
        for flag in ("--permission-prompts", "--strict-mcp-config", "--allowedTools", "--max-budget-usd"):
            if flag not in help_text:
                errors.append("Claude lacks " + flag)
        command(["gh", "auth", "status"], root)
        origin = command(["git", "remote", "get-url", "origin"], root).strip()
        repo = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?", origin)
        if not repo:
            errors.append("origin must use a canonical github.com HTTPS or SSH repository URL")
        else:
            data["repository"] = repo[1]
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        errors.append(str(exc))
    try:
        b = validate_structure(load_yaml((root / "BRIEF.yaml").read_text(encoding="utf-8")))
        data["brief"] = b
        stack, commands, _ = quality.defaults(root)
        commands.update({k: b["quality"][k] for k in commands if k in b["quality"]})
        if b["quality"]["profile"] != "docs":
            for key, value in commands.items():
                if not value:
                    errors.append("missing quality." + key + " for " + stack)
        if (root / ".claude/state/session_id").exists() and not runtime.load(root / ".claude/state/controller.json"):
            errors.append("v0.2 active state: preserve/archive it before starting v0.3; automatic migration refused")
        if (root / ".quickship/conflicts").exists():
            errors.append("installation conflicts: resolve .quickship/conflicts before running")
    except (BriefError, ValueError, OSError) as exc:
        errors.append("brief: " + str(exc))
    return data


if __name__ == "__main__":
    result = inspect(runtime.root())
    result.pop("brief", None)
    print(json.dumps(result, indent=2))
    sys.exit(2 if result["errors"] else 0)
