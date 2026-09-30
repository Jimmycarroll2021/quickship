#!/usr/bin/env python3
"""Budget status for the active run (contract: docs/design/contracts.md "Budgets").

Usage: budget.py [--transcript <path>] [--exhausted-only]
Reads $S/brief.json (exit 2 if absent), $S/started_at, $S/steps, and token usage from the
transcript JSONL plus sibling <stem>*.jsonl files (subagent transcripts, best effort).
Prints the budget JSON, or with --exhausted-only the comma-separated exhausted names. Exit 0.
"""
import argparse
import datetime as dt
import glob
import json
import os
import subprocess
import sys

MAX_BYTES = 20 * 1024 * 1024  # stop reading transcripts after this much in total
# USD per million tokens. Cache read = 10% of input; cache creation = 125% of input.
RATES = {"opus": (15.0, 75.0), "sonnet": (3.0, 15.0), "haiku": (1.0, 5.0)}
DIMS = (("tokens", "tokens"), ("cost_usd", "cost_usd"), ("elapsed_min", "wall_clock_min"), ("steps", "steps"))


def state_dir():
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if not root:
        try:
            root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                                  text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            root = "."
    return os.path.join(root, ".claude", "state")


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def rates_for(model):
    m = (model or "").lower()
    for key, r in RATES.items():
        if key in m:
            return r
    return RATES["sonnet"]


def transcript_files(path):
    if not path:
        return []
    files = [path] if os.path.isfile(path) else []
    d = os.path.dirname(path) or "."
    stem = os.path.splitext(os.path.basename(path))[0]
    for p in sorted(glob.glob(os.path.join(glob.escape(d), glob.escape(stem) + "*.jsonl"))):
        if os.path.normcase(os.path.abspath(p)) != os.path.normcase(os.path.abspath(path)):
            files.append(p)
    return files


def usage(path):
    tokens, cost, budget, seen = 0, 0.0, MAX_BYTES, set()
    for p in transcript_files(path):
        try:
            f = open(p, "rb")
        except OSError:
            continue
        with f:
            for raw in f:
                budget -= len(raw)
                if budget < 0:
                    return tokens, cost
                try:
                    msg = json.loads(raw).get("message") or {}
                    u = msg.get("usage")
                    if not isinstance(u, dict):
                        continue
                    # one API response is logged once per content block; count it once
                    mid = msg.get("id")
                    if mid:
                        if mid in seen:
                            continue
                        seen.add(mid)
                    i, o = int(u.get("input_tokens") or 0), int(u.get("output_tokens") or 0)
                    cr = int(u.get("cache_read_input_tokens") or 0)
                    cc = int(u.get("cache_creation_input_tokens") or 0)
                except (ValueError, TypeError, AttributeError):
                    continue
                rin, rout = rates_for(msg.get("model"))
                tokens += i + o + cr + cc
                cost += (i * rin + o * rout + cr * rin * 0.1 + cc * rin * 1.25) / 1e6
    return tokens, cost


def elapsed_min(started_at):
    if not started_at:
        return 0.0
    try:
        t = dt.datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    except ValueError:
        return 0.0
    if t.tzinfo is None:
        t = t.replace(tzinfo=dt.timezone.utc)
    return max(0.0, (dt.datetime.now(dt.timezone.utc) - t).total_seconds() / 60)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--transcript")
    ap.add_argument("--exhausted-only", action="store_true")
    a = ap.parse_args()
    s = state_dir()
    try:
        with open(os.path.join(s, "brief.json"), encoding="utf-8") as f:
            budgets = json.load(f).get("budgets") or {}
    except (OSError, ValueError, AttributeError) as e:
        print(f"budget: no readable brief.json in {s} ({e.__class__.__name__})", file=sys.stderr)
        return 2
    try:
        steps = int(read_text(os.path.join(s, "steps")) or 0)
    except ValueError:
        steps = 0
    tokens, cost = usage(a.transcript)
    vals = {"tokens": tokens, "cost_usd": round(cost, 4),
            "elapsed_min": round(elapsed_min(read_text(os.path.join(s, "started_at"))), 1), "steps": steps}
    limits = {lim: budgets.get(lim, 0) for _, lim in DIMS}
    exhausted = [lim for key, lim in DIMS
                 if isinstance(limits[lim], (int, float)) and limits[lim] > 0 and vals[key] >= limits[lim]]
    if a.exhausted_only:
        if exhausted:
            print(",".join(exhausted))
    else:
        print(json.dumps({**vals, "limits": limits, "exhausted": exhausted}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
