#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_strategy, DEFAULT_STRATEGY

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
src = stitch_strategy(DEFAULT_STRATEGY)
for win in ["eval_3m", "wf_2022q1"]:
    print("===", win, "===")
    for sym in ["MSFT", "IWM", "AAPL", "META", "TSLA", "SPY", "QQQ", "NVDA", "AMD", "AMZN", "GOOGL"]:
        tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
        if not tape.exists():
            continue
        m = run_gene(src, tape, execution="next-open", cost_bps=10)
        bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
        d = m.sharpe - bh.sharpe if (m.ok and bh.ok) else float("nan")
        ok = m.ok and bh.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
        mark = "PASS" if ok else "FAIL"
        print(
            f"{sym:5} sharpe={m.sharpe:+7.3f} bh={bh.sharpe:+7.3f} d={d:+7.3f} "
            f"tr={m.trades:3d} ret={m.total_return:+8.2%} mdd={m.max_drawdown:5.1%} {mark}"
        )
