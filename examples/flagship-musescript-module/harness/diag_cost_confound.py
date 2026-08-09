#!/usr/bin/env python3
"""Is ensemble_v4's lead an edge, or just lower turnover?

On heldout_v2 (9 regime folds, 300 symbols) v4 is the best variant by a wide,
statistically resolved margin (+0.294 paired vs v1, CI [+0.262, +0.326]). It also
trades 5.6 times per symbol against 12-31 for every other variant, and across the
13 variants corr(mean trades, pooled d_sharpe) = -0.64. At 10bps, trading less is
worth something all by itself.

Decisive test: re-score at ZERO cost. If v4's advantage largely survives, it is
signal. If it collapses, the "edge" was cost avoidance -- which is real money but
is NOT a forecasting edge, and would mean the honest way to capture it is simply
to trade the baseline less, not to adopt v4's logic.

Usage: python harness/diag_cost_confound.py [--variants a,b] [--folds 2014,2022]
"""
from __future__ import annotations

import argparse
import json
import statistics as st
import sys
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene_batch, stitch_source, buy_hold_source  # noqa: E402
from gate_stats import bootstrap_ci  # noqa: E402

TAPES = FLAGSHIP / "tapes" / "heldout_v2"


def score_at(name: str, fold_names: list[str], bps: float) -> dict:
    src = stitch_source(FLAGSHIP / "strategies" / f"{name}.ms")
    out = {}
    for f in fold_names:
        d = TAPES / f
        syms = sorted(p.stem for p in d.glob("*.csv"))
        jobs = [{"id": s, "source": src, "tape": str(d / f"{s}.csv"),
                 "execution": "next-open", "costBps": bps} for s in syms]
        res = run_gene_batch(jobs)
        out[f] = {s: r.sharpe for s, r in res.items() if r.ok}
    return out


def bh_at(fold_names: list[str], bps: float) -> dict:
    src = buy_hold_source()
    out = {}
    for f in fold_names:
        d = TAPES / f
        syms = sorted(p.stem for p in d.glob("*.csv"))
        jobs = [{"id": s, "source": src, "tape": str(d / f"{s}.csv"),
                 "execution": "next-open", "costBps": bps} for s in syms]
        res = run_gene_batch(jobs)
        out[f] = {s: r.sharpe for s, r in res.items() if r.ok}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", default="flagship_ensemble_v1,flagship_ensemble_v4")
    ap.add_argument("--folds", default="")
    args = ap.parse_args()

    man = json.loads((TAPES / "manifest.json").read_text())
    fold_names = args.folds.split(",") if args.folds else sorted(man["working_folds"])
    a, b = args.variants.split(",")

    print(f"folds: {', '.join(fold_names)}\ncomparing {b} vs {a}\n", file=sys.stderr)
    rows = []
    for bps in (10.0, 0.0):
        bh = bh_at(fold_names, bps)
        sa = score_at(a, fold_names, bps)
        sb = score_at(b, fold_names, bps)
        diffs, da, db = [], [], []
        for f in fold_names:
            common = set(sa[f]) & set(sb[f]) & set(bh[f])
            for s in common:
                x = sa[f][s] - bh[f][s]
                y = sb[f][s] - bh[f][s]
                da.append(x); db.append(y); diffs.append(y - x)
        mu, lo, hi = bootstrap_ci(diffs, reps=4000)
        rows.append((bps, st.mean(da), st.mean(db), mu, lo, hi, len(diffs)))
        print(f"{bps:4.1f} bps | {a} {st.mean(da):+.3f}  {b} {st.mean(db):+.3f}  "
              f"gap {mu:+.3f} [{lo:+.3f},{hi:+.3f}]  n={len(diffs)}")

    g10, g0 = rows[0][3], rows[1][3]
    print()
    print(f"gap at 10bps : {g10:+.3f}")
    print(f"gap at  0bps : {g0:+.3f}")
    if g10 != 0:
        retained = g0 / g10 * 100
        print(f"retained at zero cost: {retained:.0f}%")
        if retained < 40:
            print("=> VERDICT: mostly COST AVOIDANCE, not forecasting edge. The cheaper")
            print("   way to capture it is to cut the baseline's turnover, not adopt v4.")
        elif retained > 75:
            print("=> VERDICT: survives at zero cost -- this is signal, not turnover.")
        else:
            print("=> VERDICT: MIXED. A real part is turnover, a real part survives.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
