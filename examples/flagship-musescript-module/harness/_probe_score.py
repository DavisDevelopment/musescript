#!/usr/bin/env python3
"""Score a probe on dual liquid10 + focus cells. Args: rel [extra win:sym...]"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
L10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def cell(src: str, win: str, sym: str):
    tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe
    ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
    return ok, d, m.trades, m.sharpe, bh.sharpe


def main() -> int:
    rel = sys.argv[1]
    st = stitch_source(ROOT / "examples/flagship-musescript-module" / rel)
    print("====", Path(rel).name, "====")
    # dual
    for win in ["eval_3m", "wf_2022q1"]:
        n = 0
        bits = []
        fails = []
        ds = []
        for sym in L10:
            ok, d, tr, sh, bh = cell(st, win, sym)
            n += int(ok)
            ds.append(d)
            mark = "P" if ok else "f"
            bits.append(f"{sym}:{mark}(d={d:+.2f},tr={tr})")
            if not ok:
                fails.append(f"{sym}:d={d:+.2f}")
        print(f"  dual/{win}: {n}/10  mean_d={sum(ds)/len(ds):+.3f}")
        if fails:
            print("   fails", fails)
        else:
            print("  ", " ".join(bits[:3]), "...")
    # focus
    focus = [
        ("wf_2024q4", "AMZN"),
        ("wf_2024q4", "AMD"),
        ("wf_2024q4", "GOOGL"),
        ("wf_2024q4", "AAPL"),
        ("wf_2019q1", "MSFT"),
        ("wf_2024q4", "MSFT"),
        ("wf_2022q1", "WMT"),
        ("wf_2024q4", "WMT"),
        ("eval_3m", "WMT"),
        ("wf_2024q4", "SPY"),
        ("wf_2024q4", "QQQ"),
        ("wf_2024q4", "META"),
        ("wf_2024q4", "NVDA"),
        ("wf_2024q4", "IWM"),
        ("wf_2019q1", "IWM"),
    ]
    for extra in sys.argv[2:]:
        focus.append(tuple(extra.split(":")))
    print("  focus:")
    bulls = 0
    bull_cells = [
        ("wf_2019q1", s) for s in L10
    ] + [("wf_2024q4", s) for s in L10]
    # quick bull count
    b_ok = 0
    for win, sym in bull_cells:
        ok, d, tr, sh, bh = cell(st, win, sym)
        b_ok += int(ok)
    print(f"  BULLS liquid10: {b_ok}/20")
    for win, sym in focus:
        ok, d, tr, sh, bh = cell(st, win, sym)
        print(f"   {sym:5} {win:10} {'P' if ok else 'f'} sh={sh:+.3f} bh={bh:+.3f} d={d:+.3f} tr={tr}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
