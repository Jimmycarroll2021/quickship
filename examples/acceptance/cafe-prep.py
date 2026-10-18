#!/usr/bin/env python3
"""Hidden acceptance check for examples/ideas/cafe-prep.md.

Usage: python3 examples/acceptance/cafe-prep.py <built-project-dir>

Writes a week of till exports and prep sheets to a temporary folder, runs
`bash prep.sh <folder> <out.csv>` inside the built project, and checks the
result against what the idea promises: bestsellers that sell out by noon get
more prep, pastries that get binned get less. The agents never see this file:
scripts/init.sh does not install examples/, ship.sh copies only the idea text,
and the check refuses to run from inside the project it is checking. The
thresholds below are deliberately not in the idea.

The last line of output is PASS or FAIL. Exit 0 on PASS, 1 on FAIL, 2 on a
usage error. Env: ACCEPT_TIMEOUT, seconds allowed for prep.sh (default 300).
"""
import csv
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

DAYS = [f"2026-10-{d:02d}" for d in range(5, 12)]  # Monday 5 to Sunday 11 October
OPEN, CLOSE = 7 * 60, 15 * 60  # minutes after midnight

# item: (prepped each day, sold-out window in minutes or None, daily sold range when not sold out)
ITEMS = {
    "Almond croissant": (24, (11 * 60 + 15, 11 * 60 + 55), None),
    "Banana bread slice": (16, (14 * 60, 14 * 60 + 45), None),
    "Blueberry muffin": (30, None, (12, 16)),
    "Plain croissant": (30, None, (22, 27)),
    "Cheese scone": (12, None, (4, 8)),
}
SCONE_ZERO_DAY = 3  # Thursday: no scones sold at all, but they were still baked


def hhmm(minute):
    return f"{minute // 60:02d}:{minute % 60:02d}"


def sale_lines(rng, units, start, end, last_at=None):
    """Split units into sale lines of 1 or 2 at random minutes; the final line lands on last_at if given."""
    chunks = []
    while units > 0:
        q = 2 if units > 1 and rng.random() < 0.2 else 1
        chunks.append(q)
        units -= q
    minutes = sorted(rng.randint(start, end - 1) for _ in chunks)
    if last_at is not None:
        minutes[-1] = last_at
    return list(zip(minutes, chunks))


def write_fixtures(folder):
    """Write the week's files; return {item: [units sold per day]} and the almond sell-out times."""
    rng = random.Random(2026)
    sold = {item: [] for item in ITEMS}
    almond_times = []
    for i, day in enumerate(DAYS):
        rows = []
        for item, (prepped, window, sold_range) in ITEMS.items():
            if window:
                at = rng.randint(*window)
                lines = sale_lines(rng, prepped, OPEN, at, last_at=at)
                if item == "Almond croissant":
                    almond_times.append(at)
                units = prepped
            else:
                units = 0 if item == "Cheese scone" and i == SCONE_ZERO_DAY else rng.randint(*sold_range)
                lines = sale_lines(rng, units, OPEN, CLOSE)
            sold[item].append(units)
            rows += [(m, rng.randint(0, 59), item, q) for m, q in lines]
        rows.sort(key=lambda r: (r[0], r[1]))
        with open(folder / f"sales-{day}.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["timestamp", "item", "quantity"])
            for m, s, item, q in rows:
                w.writerow([f"{day}T{hhmm(m)}:{s:02d}", item, q])
        with open(folder / f"prep-{day}.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["item", "prepped"])
            for item, (prepped, _, _) in ITEMS.items():
                w.writerow([item, prepped])
    # files the contract says to ignore
    (folder / ".DS_Store").write_bytes(b"\x00\x00\x00\x01Bud1")
    (folder / "notes.txt").write_text("order more flour on Friday\n", encoding="utf-8")
    return sold, almond_times


class Check:
    def __init__(self):
        self.failed = 0

    def ok(self, cond, label):
        if cond:
            print(f"  ok   {label}")
        else:
            self.failed += 1
            print(f"  FAIL {label}")
        return cond

    def finish(self):
        print("FAIL" if self.failed else "PASS")
        sys.exit(1 if self.failed else 0)


def run_prep(bash, project, args, log_path, timeout):
    """Run prep.sh with output to a file; on timeout kill its whole process tree. Return exit code or None."""
    with open(log_path, "wb") as log:
        kw = {"start_new_session": True} if os.name == "posix" else {}
        proc = subprocess.Popen([bash, "prep.sh", *args], cwd=project, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, **kw)
        try:
            return proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                os.killpg(proc.pid, signal.SIGKILL)
            else:
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
                proc.kill()
            proc.wait()
            return None


def read_output(path):
    """Return ({item: quantity-string}, duplicates, header-ok) from the tool's CSV."""
    with open(path, newline="", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f)
        header = [h.strip().lower() for h in next(reader, [])]
        if "item" not in header or "quantity" not in header:
            return {}, [], False
        i, q = header.index("item"), header.index("quantity")
        rows, dupes = {}, []
        for row in reader:
            if not row or not "".join(row).strip():
                continue
            name = row[i].strip() if len(row) > i else ""
            if name in rows:
                dupes.append(name)
            rows[name] = row[q].strip() if len(row) > q else ""
        return rows, dupes, True


def main():
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(2)
    project = Path(sys.argv[1]).resolve()
    if not project.is_dir():
        print(f"accept: not a directory: {project}", file=sys.stderr)
        sys.exit(2)
    if project in Path(__file__).resolve().parents:
        print(f"accept: this check lives inside {project}, so the agents could read it; run it against a project built elsewhere", file=sys.stderr)
        sys.exit(2)
    raw_timeout = os.environ.get("ACCEPT_TIMEOUT", "300")
    if not re.fullmatch(r"[1-9]\d*", raw_timeout):
        print(f"accept: ACCEPT_TIMEOUT must be a whole number of seconds, got {raw_timeout!r}", file=sys.stderr)
        sys.exit(2)
    timeout = int(raw_timeout)
    # On Windows a bare "bash" can resolve to the WSL stub in System32; take the one on PATH (Git Bash).
    bash = shutil.which("bash")
    if not bash:
        print("accept: bash not found on PATH", file=sys.stderr)
        sys.exit(2)
    c = Check()
    print(f"accept: cafe-prep against {project}")
    if not c.ok((project / "prep.sh").is_file(), "prep.sh exists"):
        c.finish()

    with tempfile.TemporaryDirectory(prefix="cafe-prep-", ignore_cleanup_errors=True) as tmp:
        folder = Path(tmp) / "sales"
        folder.mkdir()
        out_csv = Path(tmp) / "prep.csv"
        log_path = Path(tmp) / "prep.log"
        sold, almond_times = write_fixtures(folder)
        code = run_prep(bash, project, [folder.as_posix(), out_csv.as_posix()], log_path, timeout)
        stdout = log_path.read_bytes().decode("utf-8", "replace")
        if code is None:
            c.ok(False, f"prep.sh finishes within {timeout}s")
            c.finish()
        if not c.ok(code == 0, f"prep.sh exits 0 (got {code})"):
            print("--- tail of prep.sh output ---")
            print("\n".join(stdout.strip().splitlines()[-15:]))
            c.finish()
        if not c.ok(out_csv.is_file(), "writes the output CSV"):
            c.finish()
        rows, dupes, header_ok = read_output(out_csv)

    if not c.ok(header_ok, "output CSV has item and quantity columns"):
        c.finish()
    c.ok(not dupes, f"one row per item (duplicates: {dupes or 'none'})")
    missing = sorted(set(ITEMS) - set(rows))
    extra = sorted(set(rows) - set(ITEMS))
    c.ok(not missing, f"every baked item is listed, including the scone that sold none on Thursday (missing: {missing or 'none'})")
    c.ok(not extra, f"no invented items; stray files ignored (extra: {extra or 'none'})")

    qty = {}
    for item, raw in rows.items():
        if item in ITEMS and re.fullmatch(r"\d+", raw):
            qty[item] = int(raw)
    bad = sorted(item for item in rows if item in ITEMS and item not in qty)
    c.ok(not bad, f"quantities are whole numbers (bad: {bad or 'none'})")
    wild = sorted(item for item, q in qty.items() if q > 3 * ITEMS[item][0])
    c.ok(not wild, f"no quantity above three times what was baked (too high: {wild or 'none'})")

    def judge(item, cond, label):
        if item in qty:
            c.ok(cond(qty[item]), f"{item}: {label} (suggested {qty[item]})")

    almond_by = hhmm(max(almond_times))
    judge("Almond croissant", lambda q: q > 24, f"sold out by {almond_by} every day at 24, so prep must rise above 24")
    judge("Banana bread slice", lambda q: q >= 16, "sold out every afternoon at 16, so prep must not fall below 16")
    lo = min(sold["Blueberry muffin"])
    judge("Blueberry muffin", lambda q: lo <= q < 30, f"never sold more than {max(sold['Blueberry muffin'])} of 30, so prep must fall below 30 but not below {lo}")
    judge("Cheese scone", lambda q: q < 12, f"never sold more than {max(sold['Cheese scone'])} of 12, so prep must fall below 12")

    lower = stdout.lower()
    unnamed = sorted(item for item in ITEMS if item.lower() not in lower)
    c.ok(not unnamed, f"printed list names every item (not named: {unnamed or 'none'})")
    almond_lines = [l for l in stdout.splitlines() if "almond croissant" in l.lower()]
    c.ok(any(re.search(r"\b11[:.][0-5]\d\b", l) for l in almond_lines),
         "printed list says when the almond croissant ran out (a time between 11:00 and 11:59 on its line)")
    c.finish()


if __name__ == "__main__":
    main()
