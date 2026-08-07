#!/usr/bin/env python3
"""heldout_gate.py — the promotion gate the flagship README was missing.

Every prior promotion (v6l -> v7g) was judged against the SAME 15-symbol
`tapes/` corpus the strategy was iterated against. On a genuinely broader,
untouched 54-symbol universe over the real last-8-months window, that whole
lineage underperforms plain buy-and-hold on average, and the v6l->v7e
"improvement" moved the wrong way (mean d_sharpe -0.778 -> -0.905). See
`results/BROAD8MO_REPORT.md` for the full writeup. This script is the fix:
a held-out check that must be run -- and must not regress vs. the frozen
baseline below -- before anything gets called a new champion.

Uses the warm batch runner (CURSOR_BATCH_RUNNER_SPEC / eval.run_gene_batch) --
one Node process for all 108 cells (54 symbols x {strategy, buy-hold}),
not 108 cold spawns.

Two honesty properties this script is responsible for:
  1. The held-out data is FROZEN by default (tapes/broad8mo/*.csv, fetched
     2026-08-07), not re-fetched every run. Absolute pass-rate is regime-
     dependent (a down window structurally favors this system, an up window
     structurally hurts it -- see the regime-bucket breakdown below), so
     comparing two runs is only fair when they're scored against the exact
     same window. `--refresh-data` re-fetches live data explicitly, but the
     result is then NOT comparable to the frozen baseline -- the script says
     so loudly rather than silently comparing apples to oranges.
  2. This gate reports REGRESSION vs. baseline, not an absolute bar. A
     candidate that ties the baseline passes; the bar for "better" is a
     separate, harder question this script does not claim to answer.

Usage:
  python examples/flagship-musescript-module/harness/heldout_gate.py strategies/flagship_v7g.ms
  python examples/flagship-musescript-module/harness/heldout_gate.py strategies/flagship_v7h.ms --refresh-data
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene_batch, stitch_source, buy_hold_source  # noqa: E402

TAPES = FLAGSHIP / "tapes" / "broad8mo"
DATA_SOURCE = FLAGSHIP.parents[2] / "data" / "real" / "tape_broad8mo.csv"
BASELINE_PATH = FLAGSHIP / "results" / "broad8mo_baseline.json"

REGIME_BUCKETS = [
    ("strong_up", lambda bh_ret: bh_ret > 0.15),
    ("mild", lambda bh_ret: -0.05 <= bh_ret <= 0.15),
    ("down_choppy", lambda bh_ret: bh_ret < -0.05),
]


def refresh_data() -> None:
    """Re-fetch the held-out universe live. Breaks comparability with the frozen
    baseline (a different window/data vintage) -- the caller is told this."""
    import subprocess

    tickers = ",".join(sorted(p.stem for p in TAPES.glob("*.csv")))
    fetch_script = FLAGSHIP.parents[2] / "tools" / "fetch_ohlcv.py"
    subprocess.run(
        [sys.executable, str(fetch_script), "--tickers", tickers, "--period", "2y", "--out", str(DATA_SOURCE)],
        check=True,
    )
    import csv
    import datetime as dt

    end = dt.date.today()
    start = end - dt.timedelta(days=243)  # ~8 months
    by_sym: dict[str, list[dict]] = {}
    with DATA_SOURCE.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        header = reader.fieldnames
        for row in reader:
            by_sym.setdefault(row["symbol"], []).append(row)
    for sym, rows in by_sym.items():
        sliced = [r for r in rows if start.isoformat() <= r["date"] <= end.isoformat()]
        if not sliced:
            continue
        path = TAPES / f"{sym}.csv"
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=header)
            w.writeheader()
            w.writerows(sliced)


def score(path: Path) -> dict:
    st = stitch_source(path)
    bh_src = buy_hold_source()
    syms = sorted(p.stem for p in TAPES.glob("*.csv"))

    jobs = []
    for sym in syms:
        tape = str(TAPES / f"{sym}.csv")
        jobs.append({"id": f"{sym}|strat", "source": st, "tape": tape, "execution": "next-open", "costBps": 10})
        jobs.append({"id": f"{sym}|bh", "source": bh_src, "tape": tape, "execution": "next-open", "costBps": 10})
    results = run_gene_batch(jobs)

    cells = []
    for sym in syms:
        m = results.get(f"{sym}|strat")
        bh = results.get(f"{sym}|bh")
        if m is None or not m.ok:
            cells.append({"symbol": sym, "ok": False, "error": m.error if m else "missing"})
            continue
        d = m.sharpe - bh.sharpe
        ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
        cells.append({
            "symbol": sym, "ok": True, "pass": ok,
            "sharpe": round(m.sharpe, 3), "bh_sharpe": round(bh.sharpe, 3), "d_sharpe": round(d, 3),
            "trades": m.trades, "max_dd": round(m.max_drawdown, 3),
            "total_return": round(m.total_return, 4), "bh_return": round(bh.total_return, 4),
        })

    valid = [c for c in cells if c.get("ok")]
    npass = sum(1 for c in valid if c["pass"])
    mean_d = statistics.mean(c["d_sharpe"] for c in valid) if valid else float("nan")

    regimes = {}
    for name, pred in REGIME_BUCKETS:
        bucket = [c for c in valid if pred(c["bh_return"])]
        if not bucket:
            continue
        regimes[name] = {
            "n": len(bucket),
            "mean_d_sharpe": round(statistics.mean(c["d_sharpe"] for c in bucket), 3),
            "beat_bh": sum(1 for c in bucket if c["d_sharpe"] > 0),
        }

    return {
        "strategy": path.name,
        "pass": npass,
        "total": len(valid),
        "mean_d_sharpe": round(mean_d, 3) if valid else None,
        "regimes": regimes,
        "cells": cells,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("strategy", help="relative path under strategies/, e.g. strategies/flagship_v7g.ms")
    ap.add_argument("--refresh-data", action="store_true",
                     help="re-fetch live data instead of using the frozen baseline window (breaks comparability)")
    ap.add_argument("--set-baseline", action="store_true",
                     help="write this run's result as the new baseline instead of comparing against it")
    args = ap.parse_args()

    path = FLAGSHIP / args.strategy
    if not path.exists():
        print(f"missing strategy file: {path}", file=sys.stderr)
        return 2

    if args.refresh_data:
        print("--refresh-data: re-fetching live data. Result will NOT be comparable to the frozen "
              "baseline (different window) -- reported for informational value only, not as a gate.",
              file=sys.stderr)
        refresh_data()

    result = score(path)
    print(f"{result['strategy']}: {result['pass']}/{result['total']} "
          f"(mean d_sharpe {result['mean_d_sharpe']:+.3f})")
    for name, r in result["regimes"].items():
        print(f"  {name:12s} n={r['n']:2d}  mean_d_sharpe={r['mean_d_sharpe']:+.3f}  "
              f"beat_bh={r['beat_bh']}/{r['n']}")

    if args.refresh_data:
        return 0  # informational only, not gated

    if args.set_baseline:
        BASELINE_PATH.write_text(json.dumps(result, indent=2))
        print(f"wrote new baseline: {BASELINE_PATH}")
        return 0

    if not BASELINE_PATH.exists():
        print(f"no baseline at {BASELINE_PATH} yet -- run with --set-baseline first", file=sys.stderr)
        return 2

    baseline = json.loads(BASELINE_PATH.read_text())
    regressed = (
        result["pass"] < baseline["pass"]
        or (result["mean_d_sharpe"] or -999) < (baseline["mean_d_sharpe"] or -999) - 0.02  # small noise tolerance
    )
    print(f"\nbaseline ({baseline['strategy']}): {baseline['pass']}/{baseline['total']} "
          f"(mean d_sharpe {baseline['mean_d_sharpe']:+.3f})")
    if regressed:
        print("GATE: REGRESSED vs. baseline - do not promote without understanding why.")
        return 1
    print("GATE: no regression vs. baseline.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
