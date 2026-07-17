#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from corpus_lab import TAPES, STRATEGIES, evaluate, run_backtest, split_spy, write_summary

split_spy()
bh = STRATEGIES / "00_buy_hold.ms"
bh_is = run_backtest(bh, TAPES / "spy_is_1993_2018.csv")
bh_oos = run_backtest(bh, TAPES / "spy_oos_2019_2026.csv")
hyps = {
    "20_mid_ema_time": "EMA 13/21 with 34-bar time stop",
    "23_mid_ema_time55": "EMA 13/21 with 55-bar time stop",
    "24_ema_1321_plain": "EMA 13/21 cross, no time stop",
    "25_ema_2134_time": "EMA 21/34 with 34-bar time stop",
}
for name, hyp in hyps.items():
    e = evaluate(STRATEGIES / f"{name}.ms", hyp, bh_is, bh_oos)
    late = run_backtest(STRATEGIES / f"{name}.ms", TAPES / "spy_oos_2022_2026.csv")
    print(
        f"{name}: IS={e['is_sharpe']:.3f}/{e['is_mdd']:.3f}/{e['is_ret']:.2f} "
        f"OOS={e['oos_sharpe']:.3f}/{e['oos_mdd']:.3f} d={e['oos_d_sharpe']:+.3f} "
        f"xfer={e['transfers_oos']} | late s={late.sharpe:.3f} mdd={late.max_drawdown:.3f}"
    )
write_summary(bh_is, bh_oos)
