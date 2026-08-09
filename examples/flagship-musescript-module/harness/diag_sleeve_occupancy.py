#!/usr/bin/env python3
"""Diagnostic: did v4's latch break the chop sleeve, or did v4's ENTRY RULE change?

v1 trend entry:  trendRegime && flat && close > eTrend && rising(close,3)
v4 trend entry:  trendRegime && flat                       <-- rising(close,3) dropped

Both share the same trend exit (close < eTrend || trail(3*ATR14)). While a trend
position is open, the chop sleeve cannot enter in EITHER version -- so the trend
sleeve's bar-occupancy is an upper bound on how many chop entries it can block.

This simulates the trend sleeve ALONE (entry+exit, no PnL) under each entry rule
and reports occupancy. Pure measurement off the frozen tapes -- no gate run,
no pass/fail read, zero held-out degrees of freedom consumed.
"""
import csv
import json
import statistics
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
TAPES = FLAGSHIP / "tapes" / "broad8mo"
BASELINE = FLAGSHIP / "results" / "broad8mo_baseline.json"

EMA_LEN = 34
ROC_LEN = 34
ROC_MIN = 0.07  # as written, in PERCENTAGE POINTS (MuseScript roc = pctChange*100)
ATR_LEN = 14
TRAIL_K = 3.0


def ema(xs, n):
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
    out = [None] * len(xs)
    for i in range(n, len(xs)):
        p = xs[i - n]
        if p:
            out[i] = (xs[i] - p) / p * 100.0
    return out


def atr(h, l, c, n):
    """Simple trailing mean of true range over the last n completed bars (matches
    TradeBuiltins.atr: plain mean, not Wilder RMA)."""
    tr = [None] * len(c)
    for i in range(1, len(c)):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1]))
    out = [None] * len(c)
    for m in range(len(c)):
        if m < n:
            continue
        win = tr[m - n:m]
        if any(v is None for v in win):
            continue
        out[m] = sum(win) / n
    return out


def rising(xs, i, n):
    if i < n:
        return False
    for j in range(i - n + 1, i + 1):
        if not (xs[j] - xs[j - 1] > 0):
            return False
    return True


def sim_trend_sleeve(h, l, c, require_rising):
    """Simulate the trend sleeve alone. Returns (n_entries, occupied_bars, holds)."""
    e = ema(c, EMA_LEN)
    r = roc_pp(c, ROC_LEN)
    a = atr(h, l, c, ATR_LEN)

    pos = False
    peak = None
    entries, occupied, holds, cur = 0, 0, [], 0
    for i in range(len(c)):
        if e[i] is None or r[i] is None:
            continue
        regime = c[i] > e[i] and r[i] > ROC_MIN

        if pos:
            peak = max(peak, h[i])
            dist = TRAIL_K * a[i] if a[i] is not None else None
            hit_trail = dist is not None and c[i] < peak - dist
            if c[i] < e[i] or hit_trail:
                pos = False
                holds.append(cur)
                cur = 0
                continue
            occupied += 1
            cur += 1
            continue

        # flat
        if regime and (not require_rising or rising(c, i, 3)):
            pos = True
            peak = h[i]
            entries += 1
            occupied += 1
            cur = 1
    if pos:
        holds.append(cur)
    return entries, occupied, holds


def main():
    base = json.loads(BASELINE.read_text())
    cells = {x["symbol"]: x for x in base["cells"] if x.get("ok")}

    def bucket(s):
        br = cells[s]["bh_return"]
        return "strong_up" if br > 0.15 else ("down_choppy" if br < -0.05 else "mild")

    rows = []
    for p in sorted(TAPES.glob("*.csv")):
        sym = p.stem
        rd = list(csv.DictReader(p.open(newline="", encoding="utf-8")))
        h = [float(x["high"]) for x in rd]
        l = [float(x["low"]) for x in rd]
        c = [float(x["close"]) for x in rd]
        n = len(c)
        v1 = sim_trend_sleeve(h, l, c, require_rising=True)
        v4 = sim_trend_sleeve(h, l, c, require_rising=False)
        rows.append((sym, bucket(sym), n, v1, v4, cells[sym]["trades"]))

    print("Trend-sleeve occupancy: bars the CHOP sleeve is locked out of.")
    print(f"{'sym':6s} {'bucket':11s} {'bars':>4s} | {'v1 ent':>6s} {'v1 occ%':>7s} |"
          f" {'v4 ent':>6s} {'v4 occ%':>7s} | {'v1 trades':>9s}")
    for sym, b, n, v1, v4, tr in sorted(rows, key=lambda x: (x[1], x[0])):
        print(f"{sym:6s} {b:11s} {n:4d} | {v1[0]:6d} {v1[1]/n*100:6.1f}% |"
              f" {v4[0]:6d} {v4[1]/n*100:6.1f}% | {tr:9d}")

    print()
    for b in ("strong_up", "mild", "down_choppy"):
        sub = [r for r in rows if r[1] == b]
        e1 = statistics.mean(r[3][0] for r in sub)
        o1 = statistics.mean(r[3][1] / r[2] for r in sub)
        e4 = statistics.mean(r[4][0] for r in sub)
        o4 = statistics.mean(r[4][1] / r[2] for r in sub)
        print(f"{b:11s} n={len(sub):2d} | v1 trend entries/sym {e1:5.1f}, occupancy {o1*100:5.1f}%"
              f" | v4 {e4:5.1f}, {o4*100:5.1f}%  -> occupancy x{o4/o1 if o1 else float('inf'):.2f}")


if __name__ == "__main__":
    main()
