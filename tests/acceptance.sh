#!/usr/bin/env bash
# examples/acceptance/cafe-prep.py: the hidden check must pass a sensible build and fail a naive one.
. "$(dirname "$0")/lib.sh"
CHECK="$ROOT/examples/acceptance/cafe-prep.py"
accept() { "$QS_PYTHON" "$CHECK" "$@"; }

# mkbuild <naive|smart|crash> -> a project dir whose prep.sh runs a reference prep.py in that mode
mkbuild() {
  local d; d="$(tmpdir)"
  printf '#!/usr/bin/env bash\nexec "%s" "$(dirname "$0")/prep.py" "$@"\n' "$QS_PYTHON" >"$d/prep.sh"
  printf 'MODE = "%s"\n' "$1" >"$d/prep.py"
  cat >>"$d/prep.py" <<'PYEOF'
import csv, math, sys
from pathlib import Path
if MODE == "crash":
    sys.exit("prep: cannot read folder")
folder, out = Path(sys.argv[1]), sys.argv[2]
prepped, sold, times = {}, {}, {}
for p in sorted(folder.glob("prep-*.csv")):
    day = p.stem[5:]
    for r in csv.DictReader(open(p, newline="", encoding="utf-8")):
        prepped.setdefault(r["item"], {})[day] = int(r["prepped"])
        sold.setdefault(r["item"], {})[day] = 0
for s in sorted(folder.glob("sales-*.csv")):
    day = s.stem[6:]
    for r in csv.DictReader(open(s, newline="", encoding="utf-8")):
        it = r["item"]
        before = sold[it][day]
        sold[it][day] = before + int(r["quantity"])
        if before < prepped[it][day] <= sold[it][day]:
            times.setdefault(it, []).append(r["timestamp"][11:16])
with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["item", "quantity"])
    for it in prepped:
        daily = list(sold[it].values())
        if MODE == "naive":
            q = round(sum(daily) / len(daily))
        elif it in times:
            q = math.ceil(max(prepped[it].values()) * 1.25)
        else:
            q = max(daily) + 1
        w.writerow([it, q])
        note = f" (sold out {len(times[it])} days, usually by {sorted(times[it])[len(times[it]) // 2]})" if it in times else ""
        print(f"{it}: {q}{note}")
PYEOF
  echo "$d"
}

echo "1. usage"
expect_exit "no argument exits 2" 2 accept
expect_exit "missing directory exits 2" 2 accept "$(tmpdir)/nope"
OUT="$(ACCEPT_TIMEOUT=5m accept "$(tmpdir)" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "bad ACCEPT_TIMEOUT exits 2" || bad "bad ACCEPT_TIMEOUT exit $rc: $(printf '%s' "$OUT" | tail -n 2)"
expect_exit "refuses a project that contains the check" 2 accept "$ROOT"
expect_contains "says why" "agents could read it" "$OUT"

echo "2. sensible build passes"
F="$(mkbuild smart)"
expect_exit "exit 0" 0 accept "$F"
[ "$(printf '%s\n' "$OUT" | tail -n 1)" = PASS ] && ok "final line PASS" || bad "final line: $(printf '%s' "$OUT" | tail -n 3)"

echo "3. naive build that bakes what it sold fails on the croissant"
F="$(mkbuild naive)"
expect_exit "exit 1" 1 accept "$F"
expect_contains "names the censored bestseller" "FAIL Almond croissant" "$OUT"
[ "$(printf '%s\n' "$OUT" | tail -n 1)" = FAIL ] && ok "final line FAIL" || bad "final line: $(printf '%s' "$OUT" | tail -n 3)"

echo "4. missing prep.sh fails"
expect_exit "exit 1" 1 accept "$(tmpdir)"
expect_contains "says so" "FAIL prep.sh exists" "$OUT"

echo "5. a hung child process is killed at the timeout"
F="$(tmpdir)"
printf '#!/usr/bin/env bash\n"%s" -c "import time; time.sleep(60)"\n' "$QS_PYTHON" >"$F/prep.sh"
start=$SECONDS
OUT="$(ACCEPT_TIMEOUT=2 accept "$F" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "exit 1" || bad "exit $rc: $(printf '%s' "$OUT" | tail -n 2)"
expect_contains "names the timeout" "FAIL prep.sh finishes within 2s" "$OUT"
[ $((SECONDS - start)) -lt 30 ] && ok "returns promptly ($((SECONDS - start))s)" || bad "took $((SECONDS - start))s; the child kept the check waiting"

echo "6. crashing prep.sh fails with its output"
F="$(mkbuild crash)"
expect_exit "exit 1" 1 accept "$F"
expect_contains "shows the error" "cannot read folder" "$OUT"

finish
