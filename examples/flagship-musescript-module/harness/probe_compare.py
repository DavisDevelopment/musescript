#!/usr/bin/env python3
"""Run a set of probe strategies across key cells and print a comparison table."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import (  # noqa: E402
    CONFIGS,
    RESULTS,
    STRATEGIES,
    TAPES,
    build_tapes,
    eval_batch,
    load_json,
    print_summary,
    rel,
    stitch_source,
    summarize,
)

PROBES = [
    STRATEGIES / "flagship_v0.ms",
    STRATEGIES / "probes" / "p_h1h2_no_regime_when.ms",
    STRATEGIES / "probes" / "p_h3_crown_clone.ms",
    STRATEGIES / "probes" / "p_h4_dual_sleeve.ms",
    STRATEGIES / "probes" / "p_h5_fast_dual.ms",
]

CELLS = [
    ("liquid10", "eval_3m", "any"),
    ("liquid10", "wf_2022q1", "any"),
    ("liquid10", "eval_3m", "swing"),
    ("index3", "eval_3m", "any"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--honesty", default="causal_realistic")
    args = ap.parse_args()

    batches = load_json(CONFIGS / "batches.json")
    windows = load_json(CONFIGS / "windows.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    frequencies = load_json(CONFIGS / "frequencies.json")
    if not (TAPES / "manifest.json").exists():
        build_tapes(windows, batches)

    honesty = honesty_cfg[args.honesty]
    rows = []

    for strat in PROBES:
        if not strat.exists():
            print(f"skip missing {strat}")
            continue
        source = stitch_source(strat)
        for batch, window, freq in CELLS:
            cells = eval_batch(
                source,
                batch_name=batch,
                symbols=batches[batch]["symbols"],
                window=window,
                honesty_name=args.honesty,
                honesty=honesty,
                freq_name=freq,
                freq=frequencies[freq],
                frequencies=frequencies,
            )
            s = summarize(cells)
            title = f"{strat.stem} | {batch} | {window} | freq={freq}"
            print_summary(title, s)
            rows.append(
                {
                    "strategy": strat.stem,
                    "batch": batch,
                    "window": window,
                    "frequency": freq,
                    "n_pass": s["n_pass"],
                    "n_symbols": s["n_symbols"],
                    "pass_rate": s["pass_rate"],
                    "score": s["score"],
                    "mean_sharpe": s["mean_sharpe"],
                    "mean_d_sharpe": s["mean_d_sharpe"],
                    "mean_trades": s["mean_trades"],
                    "mean_mdd": s["mean_mdd"],
                    "mean_return": s["mean_return"],
                }
            )

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / "probe_compare.json"
    out.write_text(json.dumps({"honesty": args.honesty, "rows": rows}, indent=2), encoding="utf-8")

    print("\n=== COMPARISON (sorted by pass_rate, score) ===")
    print(
        f"{'strategy':28} {'cell':32} {'pass':7} {'score':7} {'sharpe':7} {'dBH':7} {'trades':7}"
    )
    for r in sorted(rows, key=lambda x: (-x["pass_rate"], -x["score"])):
        cell = f"{r['batch']}/{r['window']}/{r['frequency']}"
        trades = r["mean_trades"] if r["mean_trades"] is not None else 0
        print(
            f"{r['strategy']:28} {cell:32} "
            f"{r['n_pass']}/{r['n_symbols']:<5} "
            f"{r['score']:7.3f} {r['mean_sharpe']:7.3f} {r['mean_d_sharpe']:7.3f} {trades:7.2f}"
        )
    print(f"\nwrote {rel(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
