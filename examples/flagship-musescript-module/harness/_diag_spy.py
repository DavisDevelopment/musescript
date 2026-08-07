#!/usr/bin/env python3
"""Diagnose SPY bar1 fo + peak path across windows vs v7d."""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(MOD / "harness"))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"


def bar1_fo(win: str, sym: str) -> float:
    rows = list(csv.DictReader((MOD / f"tapes/{win}/{sym}.csv").open()))
    r1 = rows[1]
    fo = (float(r1["close"]) - float(r1["open"])) / float(r1["open"])
    print(f"{sym:5} {win:10} bar1 fo={fo:+.4%} o={float(r1['open']):.2f} c={float(r1['close']):.2f} n={len(rows)}")
    return fo


def peak(win: str, sym: str) -> None:
    rows = list(csv.DictReader((MOD / f"tapes/{win}/{sym}.csv").open()))
    o1 = float(rows[1]["open"])
    best = (-1e9, -1, 0.0)
    for i, r in enumerate(rows):
        fo = (float(r["close"]) - o1) / o1
        if fo > best[0]:
            best = (fo, i, float(r["close"]))
    end = (float(rows[-1]["close"]) - o1) / o1
    print(f"  peak fo_b1o={best[0]:+.4%} @bar={best[1]}  end={end:+.4%}")


def main() -> int:
    gene = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_v7d.ms"
    st = stitch_source(MOD / gene)
    print("==== bar1 fo SPY ====")
    for win in ["wf_2019q1", "wf_2024q4", "eval_3m", "wf_2022q1"]:
        bar1_fo(win, "SPY")
        peak(win, "SPY")
    print("==== scores ====")
    for win in ["wf_2019q1", "wf_2024q4", "eval_3m", "wf_2022q1"]:
        tape = MOD / f"tapes/{win}/SPY.csv"
        m = run_gene(st, tape, execution="next-open", cost_bps=10)
        bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
        d = m.sharpe - bh.sharpe
        print(
            f"SPY {win:10} sh={m.sharpe:+.3f} bh={bh.sharpe:+.3f} d={d:+.3f} "
            f"tr={m.trades} ret={m.total_return:+.3%} bhret={bh.total_return:+.3%}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
