#!/usr/bin/env python3
"""Score flagship_v3 vs v2 on liquid10."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def score(label: str, path: Path) -> None:
    stitched = stitch_source(path)
    print(f"\n===== {label} =====")
    for win in ["eval_3m", "wf_2022q1"]:
        n_pass = n = 0
        fails = []
        for sym in SYMS:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            n += 1
            if not m.ok:
                fails.append(f"{sym}:ERR")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}/sh={m.sharpe:+.2f}/ret={m.total_return:+.1%}")
        print(f"  {win}: {n_pass}/{n}")
        if fails:
            print(f"    fails: {fails}")


def main() -> int:
    base = ROOT / "examples/flagship-musescript-module/strategies"
    score("v2", base / "flagship_v2.ms")
    score("v3", base / "flagship_v3.ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
