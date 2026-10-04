"""Mission supervisor and sole publisher. All external mutations use literal argv."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import runtime
import quality
import preflight
import policy
import budget
import check_criteria
import agent_hook

EXITS = {"DONE": 0, "DONE_PARTIAL": 3, "SAFE_STOP": 3, "HALT": 4, "ERROR": 5}


def now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(args, root, timeout=30, check=True):
    p = subprocess.run(args, cwd=root, capture_output=True, text=True, timeout=max(.1, timeout))
    if check and p.returncode:
        raise ValueError("command failed: " + shlex.join(args[:3]) + ": " + p.stderr[-1000:])
    return p.stdout.strip()


def hashes(root):
    paths = run(["git", "ls-files"], root).splitlines()
    # Include installed harness entries even before the operator commits them.
    manifest = root / ".quickship/manifest.sha256"
    if manifest.exists():
        paths += [x.split("  ", 1)[1] for x in manifest.read_text().splitlines() if "  " in x]
    paths += ["BRIEF.yaml"]
    for directory in ("scripts", ".claude/agents"):
        paths += [str(p.relative_to(root)).replace("\\", "/") for p in (root / directory).rglob("*")
                  if p.is_file() and "__pycache__" not in p.parts]
    result = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in set(paths)
              if (policy.harness_file(p) or p == "BRIEF.yaml") and (root / p).is_file()}
    origin = run(["git", "remote", "get-url", "origin"], root, check=False)
    result["__origin__"] = hashlib.sha256(origin.encode()).hexdigest()
    return result


def finish(root, state, reason, details=None, retryable=False):
    # retryable: a plain rerun can resume this run (the lead crashed or an exception interrupted the controller).
    result = {"schema": 3, "state": state, "reason": reason, "at": now(), "retryable": retryable, **(details or {})}
    runtime.atomic(root / "docs/RUN_STATE", {k: result[k] for k in ("state", "reason", "at")})
    runtime.atomic(root / "docs/COMPLETION.json", result)
    report = root / "docs/REPORT.md"
    previous = report.read_text(encoding="utf-8") if report.exists() else ""
    # Replace the authoritative heading on resume, preserving the agent's details.
    if "<!-- quickship-controller-end -->" in previous:
        previous = previous.split("<!-- quickship-controller-end -->", 1)[1].lstrip()
    heading = "# Verified mission outcome\n\nState: **" + state + "**\n\nReason: " + reason + "\n\n"
    if details:
        heading += "```json\n" + json.dumps(details, indent=2) + "\n```\n\n"
    rendered = heading + "<!-- quickship-controller-end -->\n\n" + previous
    with runtime.transaction() as db:
        runtime.put(db, "controller-report", {"body": previous, "rendered": rendered})
    runtime.atomic(report, rendered)
    print("run: state=" + state + " reason=" + reason, flush=True)
    return EXITS[state]


def restore_controller_report(root):
    """Undo only our exact last heading before handing a resumed report to the lead."""
    report = root / "docs/REPORT.md"
    with runtime.transaction() as db:
        record = runtime.get(db, "controller-report", {})
    if record and report.exists() and report.read_text(encoding="utf-8") == record["rendered"]:
        runtime.atomic(report, record["body"])


def terminate(proc):
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
    else:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    proc.wait(timeout=10)


def launch(args, root, output, deadline, env, cancellation=True):
    if args[0] == "claude" and os.name == "nt":
        args = [quality.bash(), "-c", "exec " + shlex.join(args)]
    with open(output, "w", encoding="utf-8", newline="\n") as f:
        p = subprocess.Popen(args, cwd=root, stdout=f, stderr=subprocess.PIPE, text=True,
                             env=env, start_new_session=os.name != "nt")
        # stderr must be drained: otherwise a chatty child can deadlock on the pipe.
        import threading
        errors = []
        thread = threading.Thread(target=lambda: errors.extend(p.stderr), daemon=True)
        thread.start()
        reason = None
        try:
            while p.poll() is None:
                if time.time() >= deadline:
                    reason = "wall-clock deadline exceeded"
                elif cancellation and (runtime.state() / "cancel").exists():
                    reason = "cancelled"
                if reason:
                    terminate(p)
                    break
                time.sleep(.2)
        except BaseException:
            terminate(p)
            raise
        finally:
            thread.join(timeout=2)
            p.stderr.close()
        if errors:
            runtime.atomic(runtime.state() / "last_stderr.txt", "".join(errors))
        return p.returncode, reason


def remaining(config):
    return max(.1, config["deadline"] - time.time())


def agents(root):
    from brief import load_yaml
    result = {}
    for path in sorted((root / ".claude/agents").glob("*.md")):
        _, frontmatter, prompt = path.read_text(encoding="utf-8").split("---", 2)
        fields = load_yaml(frontmatter)
        name = fields.pop("name")
        fields["prompt"] = prompt.strip()
        for key in ("tools", "disallowedTools"):
            if isinstance(fields.get(key), str):
                fields[key] = [t.strip() for t in fields[key].split(",")]
        result[name] = fields
    return result


def verify_criteria(root, brief, config):
    results = []
    for index, criterion in enumerate(brief["success_criteria"]):
        if criterion["kind"] == "judge":
            with runtime.transaction() as db:
                grade = runtime.get(db, "judge:" + str(index), {})
            status, detail = "fail", "judge has no matching actual reviewer evidence"
            if grade.get("rubric") == criterion["rubric"] and grade.get("artifacts") == agent_hook.artifacts(brief) and grade.get("evidence"):
                status = "pass" if grade["verdict"] == "PASS" else "fail"
                detail = grade["verdict"] + "; evidence: " + grade["evidence"]
        else:
            check_criteria.TEST_TIMEOUT_S = min(600, remaining(config))
            status, detail = check_criteria.evaluate(criterion, root)
        results.append({"kind": criterion["kind"], "status": status, "detail": detail})
    data = check_criteria.recount(results)
    return data


def publish(root, config, branch, head):
    def command(args, root, timeout=30):
        if time.time() >= config["deadline"]:
            raise ValueError("wall-clock deadline exceeded during publication")
        return run(args, root, timeout=min(timeout, remaining(config)))

    brief = config["brief"]
    repository = config.get("repository")
    repo_flags = ["--repo", repository] if repository else []
    base = brief["mission"].get("base") or command(["gh", "repo", "view", *([repository] if repository else []), "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], root)
    if branch == base or not re.fullmatch(r"mission/[a-z0-9][a-z0-9/-]*", branch):
        raise policy.Denied("publish requires a mission branch")
    policy.authorize("git push origin " + branch, brief)
    policy.authorize("gh pr create --base " + base, brief)
    # Reservation is run-wide, independent of the model's active step.
    with runtime.transaction() as db:
        record = runtime.get(db, "publication", {})
        if record and (record.get("branch"), record.get("base")) != (branch, base):
            raise ValueError("publication reservation differs from current mission")
        if not record:
            record = {"branch": branch, "base": base, "status": "pending"}
            runtime.put(db, "publication", record)
    # Reconcile remote state before every mutation, including crash recovery.
    remote = command(["git", "ls-remote", "origin", "refs/heads/" + branch], root)
    if not remote or remote.split()[0] != head:
        command(["git", "push", "origin", branch], root, timeout=remaining(config))
    prs = json.loads(command(["gh", "pr", "list", "--state", "open", "--head", branch, "--base", base,
                         "--json", "url,headRefOid,headRefName,baseRefName", *repo_flags], root))
    if len(prs) > 1:
        raise ValueError("multiple matching PRs; refusing duplicate publication")
    if not prs:
        body = runtime.state() / "pr-body.md"
        runtime.atomic(body, "Mission: " + brief["mission"]["goal"] +
                       "\n\nThe controller independently verified the final gate, success criteria, deliverables and security review.\n")
        command(["gh", "pr", "create", "--head", branch, "--base", base, "--title", brief["mission"]["goal"][:200],
             "--body-file", str(body), *repo_flags], root, timeout=remaining(config))
        prs = json.loads(command(["gh", "pr", "list", "--state", "open", "--head", branch, "--base", base,
                             "--json", "url,headRefOid,headRefName,baseRefName", *repo_flags], root))
    if len(prs) != 1 or prs[0]["headRefOid"] != head or prs[0]["headRefName"] != branch or prs[0]["baseRefName"] != base:
        raise ValueError("PR head/base/SHA verification failed")
    remote = command(["git", "ls-remote", "origin", "refs/heads/" + branch], root)
    if not remote or remote.split()[0] != head:
        raise ValueError("remote branch SHA verification failed")
    record.update({"status": "verified", "head": head, "url": prs[0]["url"]})
    with runtime.transaction() as db:
        runtime.put(db, "publication", record)
    return record


def finalize(root, config):
    if hashes(root) != config["hashes"]:
        return finish(root, "HALT", "active harness or brief changed")
    candidate = runtime.load(root / "docs/RESULT.json")
    if not isinstance(candidate, dict) or candidate.get("state") not in ("READY", "DONE_PARTIAL", "SAFE_STOP", "HALT"):
        return finish(root, "ERROR", "lead ended without a valid RESULT.json")
    if candidate["state"] != "READY":
        return finish(root, candidate["state"], candidate.get("reason", "lead submitted incomplete result"))
    if time.time() >= config["deadline"]:
        return finish(root, "DONE_PARTIAL", "deadline exceeded before final verification")
    b = config["brief"]
    transcript = budget.normalize_path(budget.read_text(runtime.state() / "transcript_path"))
    if not transcript or not Path(transcript).is_file():
        return finish(root, "DONE_PARTIAL", "final budget accounting unavailable")
    tokens, cache_reads, cost = budget.incremental_usage(transcript)
    steps = int(budget.read_text(runtime.state() / "steps") or "0")
    exhausted = [key for key, value in (("tokens", tokens), ("cost_usd", cost), ("steps", steps))
                 if value >= b["budgets"][key]]
    if exhausted:
        return finish(root, "DONE_PARTIAL", "budget exhausted before final verification", {"exhausted": exhausted})
    gate = quality.gate(root, b, config["deadline"])
    criteria = verify_criteria(root, b, config)
    missing = []
    for name in b["mission"]["deliverables"]:
        path = policy.resolve_path(name, root)
        tracked = run(["git", "ls-files", "--", name], root)
        if not policy.inside(path, root) or not path.exists() or not tracked:
            missing.append(name)
    head = run(["git", "rev-parse", "HEAD"], root)
    with runtime.transaction() as db:
        security = runtime.get(db, "security", {})
    details = {"head": head, "gate": gate, "criteria": criteria, "missing": missing, "security": security}
    if not gate["pass"] or criteria["failed"] or criteria["deferred"] or missing or security.get("verdict") != "PASS" or security.get("head") != head:
        return finish(root, "DONE_PARTIAL", "final verification incomplete or failed", details)
    if run(["git", "diff", "--name-only", "HEAD"], root):
        return finish(root, "DONE_PARTIAL", "uncommitted tracked changes remain", details)
    untracked = set(run(["git", "ls-files", "--others", "--exclude-standard"], root).splitlines())
    if untracked - {"docs/RESULT.json", "docs/COMPLETION.json", "docs/RUN_STATE", "docs/PROGRAM.md"}:
        return finish(root, "DONE_PARTIAL", "uncommitted project files remain", details)
    if time.time() >= config["deadline"]:
        return finish(root, "DONE_PARTIAL", "deadline exceeded during final verification", details)
    if hashes(root) != config["hashes"]:
        return finish(root, "HALT", "harness changed during verification", details)
    branch = run(["git", "branch", "--show-current"], root)
    try:
        details["publication"] = publish(root, config, branch, head)
    except policy.Denied as exc:
        return finish(root, "DONE_PARTIAL", str(exc), details)
    if time.time() >= config["deadline"]:
        return finish(root, "DONE_PARTIAL", "deadline exceeded during publication", details)
    return finish(root, "DONE", "criteria, gate, security, branch and PR independently verified", details)


def main():
    root = runtime.root()
    try:
        check = preflight.inspect(root)
        if check["errors"]:
            print(json.dumps({"preflight": check["errors"]}, indent=2), file=sys.stderr)
            return 2
        config = runtime.load(runtime.state() / "controller.json")
        if config and config.get("schema") != 3:
            print("run: incompatible runtime schema; archive explicitly", file=sys.stderr)
            return 2
        b = check["brief"]
        if config and config["brief"] != b:
            completed = runtime.load(root / "docs/COMPLETION.json", {})
            if completed.get("state") != "DONE" or config["brief"]["mission"]["goal"] == b["mission"]["goal"]:
                print("run: active brief differs; preserve/archive run before changing it", file=sys.stderr)
                return 2
        run([sys.executable, "scripts/brief.py", "validate"], root)
        run([sys.executable, "scripts/ledger.py", "archive-stale"], root)
        config = runtime.load(runtime.state() / "controller.json")
        if not config:
            started = dt.datetime.fromisoformat((runtime.state() / "started_at").read_text().strip().replace("Z", "+00:00")).timestamp()
            config = {"schema": 3, "brief": b, "deadline": started + b["budgets"]["wall_clock_min"] * 60,
                      "hashes": hashes(root), "auth": check["auth"], "repository": check.get("repository")}
            runtime.atomic(runtime.state() / "controller.json", config)
        terminal = runtime.load(root / "docs/COMPLETION.json")
        if terminal and terminal.get("schema") == 3 and terminal["state"] in ("DONE", "HALT"):
            return EXITS.get(terminal["state"], 5)
        if hashes(root) != config["hashes"]:
            return finish(root, "HALT", "active harness or brief changed before resume")
        if time.time() >= config["deadline"]:
            return finish(root, "DONE_PARTIAL", "wall-clock deadline exceeded")
        used_steps = int(budget.read_text(runtime.state() / "steps") or "0")
        if used_steps >= b["budgets"]["steps"]:
            return finish(root, "DONE_PARTIAL", "step budget exhausted before launch")
        remembered = budget.normalize_path(budget.read_text(runtime.state() / "transcript_path"))
        if remembered:
            if not Path(remembered).is_file():
                return finish(root, "SAFE_STOP", "saved transcript missing; resume accounting unavailable")
            used_tokens, _, used_cost = budget.incremental_usage(remembered)
            if used_tokens >= b["budgets"]["tokens"] or used_cost >= b["budgets"]["cost_usd"]:
                return finish(root, "DONE_PARTIAL", "resource budget exhausted before launch")
        with runtime.transaction() as db:
            attempts = runtime.increment(db, "launches")
        if attempts > 5:
            return finish(root, "SAFE_STOP", "restart limit (5) reached")
        if attempts > 1:
            time.sleep(min(float(os.environ.get("QS_SLEEP", 2 ** (attempts - 1))), remaining(config)))
        restore_controller_report(root)
        sid_path = runtime.state() / "session_id"
        sid = sid_path.read_text().strip() if sid_path.exists() else ""
        settings = runtime.load(root / ".claude/settings.json")
        # Freeze hook scripts and settings outside the project checkout for the lifetime of this invocation.
        with tempfile.TemporaryDirectory(prefix="quickship-controller-") as temporary:
            frozen = Path(temporary)
            shutil.copytree(root / "scripts", frozen / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
            for entries in settings["hooks"].values():
                for entry in entries:
                    for hook in entry.get("hooks", []):
                        hook["command"] = hook["command"].replace('$CLAUDE_PROJECT_DIR', str(frozen).replace("\\", "/"))
            settings_path = frozen / "settings.json"
            runtime.atomic(settings_path, settings)
            agents_path = frozen / "agents.json"
            runtime.atomic(agents_path, agents(root))
            args = ["claude", "-p", "Run the mission in BRIEF.yaml using the v0.3 Lead loop. Nobody is answering questions. "
                    "Do not push, open or merge PRs. Submit docs/RESULT.json and docs/REPORT.md when ready. "
                    "Bind each subagent to its registered step before work. Reserve 25% of the budgets for synthesis.",
                    "--permission-mode", "acceptEdits", "--permission-prompts", "none",
                    "--allowedTools", ",".join(settings["permissions"]["allow"]),
                    "--settings", str(settings_path), "--setting-sources", "",
                    "--agents", str(agents_path),
                    "--mcp-config", '{"mcpServers":{}}', "--strict-mcp-config", "--output-format", "json",
                    "--max-turns", str(int(b["budgets"]["steps"]))]
            if sid:
                args += ["--resume", sid]
            if check["auth"].get("authMethod") != "claude.ai":
                api_used_cost = 0.0
                if (runtime.state() / "transcript_path").exists():
                    data = json.loads(run([sys.executable, "scripts/budget.py"], root))
                    api_used_cost = data["cost_usd"]
                allowance = b["budgets"]["cost_usd"] - api_used_cost
                if allowance < .01:
                    return finish(root, "DONE_PARTIAL", "API budget remaining is below one cent")
                args += ["--max-budget-usd", str(allowance)]
            env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root), QS_HARNESS_ROOT=str(frozen),
                       CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS="1")
            ov = None
            if os.environ.get("QS_OVERSEER", "1") == "1":
                # The loop is supervised alongside the lead; terminate the whole owned tree on exit.
                log = open(runtime.state() / "overseer-process.log", "w", encoding="utf-8")
                ov = subprocess.Popen([quality.bash(), str(frozen / "scripts/overseer.sh"), "--loop",
                    os.environ.get("QS_OVERSEER_MIN", "15")], cwd=root, env=env, stdout=log, stderr=log,
                    start_new_session=os.name != "nt")
            try:
                rc, reason = launch(args, root, runtime.state() / "last_run.json", config["deadline"], env)
            finally:
                if ov:
                    terminate(ov)
                    log.close()
            try:
                data = runtime.load(runtime.state() / "last_run.json", {})
            except ValueError:
                data = {}
            if data.get("session_id"):
                runtime.atomic(sid_path, data["session_id"] + "\n")
            elif (runtime.state() / "transcript_path").exists():
                tp = (runtime.state() / "transcript_path").read_text().strip().replace("\\", "/")
                runtime.atomic(sid_path, Path(tp).stem + "\n")
            if reason:
                return finish(root, "SAFE_STOP" if reason == "cancelled" else "DONE_PARTIAL", reason)
            if rc or data.get("is_error"):
                return finish(root, "SAFE_STOP", "Claude session failed; inspect last_stderr and resume evidence",
                              {"lead_exit": rc}, retryable=True)
            return finalize(root, config)
    except KeyboardInterrupt:
        return finish(root, "SAFE_STOP", "interrupted; session and ledgers preserved")
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        return finish(root, "ERROR", str(exc), retryable=True)


if __name__ == "__main__":
    try:
        with runtime.file_lock("controller.lock"):
            sys.exit(main())
    except TimeoutError:
        print("run: another controller is active; no state changed", file=sys.stderr)
        sys.exit(2)
