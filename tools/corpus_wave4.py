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
    "21_fast_ema_longtime": "EMA 8/21 with 55-bar time stop",
    "22_fast_ema_slow_exit": "EMA 8/21 entry, exit vs EMA34 + time stop",
}
for name, hyp in hyps.items():
    e = evaluate(STRATEGIES / f"{name}.ms", hyp, bh_is, bh_oos)
    print(
        f"{name}: IS s={e['is_sharpe']:.3f} OOS s={e['oos_sharpe']:.3f} "
        f"d={e['oos_d_sharpe']:+.3f} mdd={e['oos_mdd']:.3f} xfer={e['transfers_oos']}"
    )
    r = run_backtest(STRATEGIES / f"{name}.ms", TAPES / "spy_oos_2022_2026.csv")
    print(f"  late2022+: s={r.sharpe:.3f} mdd={r.max_drawdown:.3f} ret={r.total_return:.3f}")
write_summary(bh_is, bh_oos)
for name in ["07_ema_time_stop", "16_fast_ema_time", "18_macd_soft_trend", "00_buy_hold"]:
    r = run_backtest(STRATEGIES / f"{name}.ms", TAPES / "spy_oos_2022_2026.csv")
    print(f"holdout {name}: s={r.sharpe:.3f} mdd={r.max_drawdown:.3f} ret={r.total_return:.3f}")
