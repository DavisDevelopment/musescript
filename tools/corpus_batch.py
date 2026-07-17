#!/usr/bin/env python3
"""Evaluate all corpus strategies and print a ranked table."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from corpus_lab import (  # noqa: E402
    RESULTS,
    STRATEGIES,
    TAPES,
    evaluate,
    run_backtest,
    split_spy,
    write_summary,
)

HYPOTHESES = {
    "00_buy_hold": "Baseline buy-and-hold from bar 55",
    "01_golden_cross": "Fib 55/89 SMA golden cross trend follow",
    "02_sma_cross_fast": "Fast 8/21 SMA cross for medium swings",
    "03_rsi_mean_rev": "RSI(13) mean-reversion long-only",
    "04_rsi_dip_trend": "RSI dips only while price above SMA89",
    "05_donchian": "Donchian 21-high entry / 8-low exit",
    "06_dual_ma_hard_stop": "21/55 SMA cross with 8% equity hard stop",
    "07_ema_time_stop": "EMA 13/34 with 55-bar time stop",
    "08_macd_hist": "MACD histogram regime (long when hist>0)",
    "09_atr_squeeze": "ATR compression then 21d breakout",
    "10_sma_cross_trend": "8/21 SMA cross only above SMA89 trend filter",
    "11_sma_cross_mid": "13/34 SMA cross medium trend",
    "12_sma_mid_stop": "13/34 SMA cross with 6% equity stop",
    "13_donchian_trend": "Donchian 21 breakout only above SMA89",
    "14_macd_trend": "MACD hist>0 only above SMA89",
    "15_ema_trend_time": "EMA 13/34 + SMA89 filter + 55-bar time stop",
    "16_fast_ema_time": "EMA 8/21 with 34-bar time stop",
    "17_sma_fast_time": "SMA 8/21 with 34-bar time stop",
    "18_macd_soft_trend": "MACD hist>0 above SMA55 (softer trend)",
    "19_ema_time_hard": "EMA 13/34 time stop + 5% equity hard stop",
}


def main() -> int:
    split_spy()
    bh = STRATEGIES / "00_buy_hold.ms"
    bh_is = run_backtest(bh, TAPES / "spy_is_1993_2018.csv")
    bh_oos = run_backtest(bh, TAPES / "spy_oos_2019_2026.csv")
    print(f"BH IS sharpe={bh_is.sharpe:.4f} mdd={bh_is.max_drawdown:.4f} ret={bh_is.total_return:.4f}")
    print(f"BH OOS sharpe={bh_oos.sharpe:.4f} mdd={bh_oos.max_drawdown:.4f} ret={bh_oos.total_return:.4f}")

    ledger = RESULTS / "ledger.jsonl"
    if ledger.exists():
        ledger.unlink()

    entries = []
    for path in sorted(STRATEGIES.glob("*.ms")):
        if path.name.startswith("_"):
            continue
        hyp = HYPOTHESES.get(path.stem, path.stem)
        print(f"\n=== {path.name} ===")
        entry = evaluate(path, hyp, bh_is, bh_oos)
        entries.append(entry)
        print(
            f"  IS  sharpe={entry.get('is_sharpe')} trades={entry.get('is_trades')} err={entry.get('is_error')}"
        )
        print(
            f"  OOS sharpe={entry.get('oos_sharpe')} d={entry.get('oos_d_sharpe')} "
            f"mdd={entry.get('oos_mdd')} transfers={entry.get('transfers_oos')} err={entry.get('oos_error')}"
        )

    write_summary(bh_is, bh_oos)
    winners = [e for e in entries if e.get("transfers_oos") == "yes"]
    print("\n=== WINNERS ===")
    print(json.dumps(winners, indent=2))
    ranked = sorted(
        [e for e in entries if e.get("oos_sharpe") is not None],
        key=lambda e: (e.get("oos_d_sharpe") or -999),
        reverse=True,
    )
    print("\n=== RANKED BY OOS dSHARPE ===")
    for e in ranked:
        print(
            f"{e['name']:28s} oos_s={e['oos_sharpe']:.3f} d={e['oos_d_sharpe']:+.3f} "
            f"mdd={e['oos_mdd']:.3f} xfer={e['transfers_oos']}"
        )
    return 0 if winners else 2


if __name__ == "__main__":
    raise SystemExit(main())
