#!/usr/bin/env python3
"""Diagnostic: quantify the roc() units bug in the ensemble regime gate.

trendRegime = close > ema(close,34) && roc(close,34) > trendRocMin, trendRocMin=0.07.
MuseScript roc() returns PERCENTAGE POINTS (pctChange*100), so the live gate is
"up more than 0.07% over 34 bars" -- not the 7% the comments claim.

Measures, per broad8mo symbol: in-regime bar fraction and on-segment structure
under the as-written threshold (0.07pp) vs the evidently intended one (7pp).
No backtest, no gate submission -- pure measurement off the frozen tapes.
"""
import csv
import json
import statistics
import sys
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
TAPES = FLAGSHIP / "tapes" / "broad8mo"
BASELINE = FLAGSHIP / "results" / "broad8mo_baseline.json"

LEN = 34


def ema(xs, n):
    """SMA-seeded EMA, NaN before warmup."""
    out = [None] * len(xs)
    if len(xs) < n:
        return out
    k = 2.0 / (n + 1.0)
    prev = sum(xs[:n]) / n
    out[n - 1] = prev
    for i in range(n, len(xs)):
        prev = xs[i] * k + prev * (1 - k)
        out[i] = prev
    return out


def roc_pp(xs, n):
    """MuseScript roc(): pctChange*100 -> percentage points."""
    out = [None] * len(xs)
    for i in range(n, len(xs)):
        prev = xs[i - n]
        if prev:
            out[i] = (xs[i] - prev) / prev * 100.0
    return out


def segments(flags):
    """Lengths of consecutive True runs."""
    segs, run = [], 0
    for f in flags:
        if f:
            run += 1
        elif run:
            segs.append(run)
            run = 0
    if run:
        segs.append(run)
    return segs


def load(sym):
    rows = list(csv.DictReader((TAPES / f"{sym}.csv").open(newline="", encoding="utf-8")))
    return [float(r["close"]) for r in rows]


def analyze(closes, thresh_pp):
    e = ema(closes, LEN)
    r = roc_pp(closes, LEN)
    flags = [
        (e[i] is not None and r[i] is not None and closes[i] > e[i] and r[i] > thresh_pp)
        for i in range(len(closes))
    ]
    valid = sum(1 for i in range(len(closes)) if e[i] is not None and r[i] is not None)
    segs = segments(flags)
    on = sum(flags)
    return {
        "bars": len(closes),
        "valid": valid,
        "on": on,
        "frac": on / valid if valid else 0.0,
        "nseg": len(segs),
        "segs": segs,
        # flicker = fraction of segments that are 1-2 bars (noise blips)
        "blips": sum(1 for s in segs if s <= 2),
        "median_seg": statistics.median(segs) if segs else 0,
        "max_seg": max(segs) if segs else 0,
    }


def main():
    base = json.loads(BASELINE.read_text())
    cells = {c["symbol"]: c for c in base["cells"] if c.get("ok")}

    def bucket(sym):
        br = cells[sym]["bh_return"]
        return "strong_up" if br > 0.15 else ("down_choppy" if br < -0.05 else "mild")

    syms = sorted(p.stem for p in TAPES.glob("*.csv"))
    rows = []
    for sym in syms:
        closes = load(sym)
        rows.append((sym, bucket(sym), analyze(closes, 0.07), analyze(closes, 7.0)))

    print(f"{'sym':6s} {'bucket':11s} | {'as-written (>0.07pp)':>28s} | {'intended (>7pp)':>28s}")
    print(f"{'':6s} {'':11s} | {'on%':>5s} {'segs':>5s} {'blip':>5s} {'med':>4s} {'max':>4s} |"
          f" {'on%':>5s} {'segs':>5s} {'blip':>5s} {'med':>4s} {'max':>4s}")
    for sym, b, a, w in sorted(rows, key=lambda x: (x[1], x[0])):
        print(f"{sym:6s} {b:11s} | {a['frac']*100:5.1f} {a['nseg']:5d} {a['blips']:5d} "
              f"{a['median_seg']:4.0f} {a['max_seg']:4d} | "
              f"{w['frac']*100:5.1f} {w['nseg']:5d} {w['blips']:5d} {w['median_seg']:4.0f} {w['max_seg']:4d}")

    print()
    for b in ("strong_up", "mild", "down_choppy"):
        sub = [r for r in rows if r[1] == b]
        if not sub:
            continue
        for label, idx in (("as-written >0.07pp", 2), ("intended  >7pp   ", 3)):
            fr = statistics.mean(r[idx]["frac"] for r in sub)
            ns = statistics.mean(r[idx]["nseg"] for r in sub)
            bl = sum(r[idx]["blips"] for r in sub)
            tot = sum(r[idx]["nseg"] for r in sub)
            print(f"{b:11s} n={len(sub):2d}  {label}: in-regime {fr*100:5.1f}%  "
                  f"segs/sym {ns:5.1f}  1-2bar blips {bl}/{tot} ({bl/tot*100 if tot else 0:4.1f}%)")
        print()


if __name__ == "__main__":
    sys.exit(main())
