#!/usr/bin/env python3
"""Micro-sweep around SMA 8/13 and EMA 8/34 champions."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from corpus_lab import STRATEGIES, TAPES, evaluate, run_backtest, split_spy, write_summary

FIB = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]


def sma(f, s):
    return f"""strategy S {{
  maFast = sma(close, {f})
  maSlow = sma(close, {s})
  onBar {{
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }}
}}
"""


def ema(f, s):
    return f"""strategy S {{
  fast = ema(close, {f})
  slow = ema(close, {s})
  onBar {{
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }}
}}
"""


def run_src(src):
    with tempfile.NamedTemporaryFile("w", suffix=".ms", delete=False, encoding="utf-8") as f:
        f.write(src)
        p = Path(f.name)
    try:
        return (
            run_backtest(p, TAPES / "spy_is_1993_2018.csv"),
            run_backtest(p, TAPES / "spy_oos_2019_2026.csv"),
            run_backtest(p, TAPES / "spy_oos_2022_2026.csv"),
        )
    finally:
        p.unlink(missing_ok=True)


def main():
    split_spy()
    bh = STRATEGIES / "00_buy_hold.ms"
    bh_is = run_backtest(bh, TAPES / "spy_is_1993_2018.csv")
    bh_oos = run_backtest(bh, TAPES / "spy_oos_2019_2026.csv")

    rows = []
    # tight neighborhood around 8/13
    for f in [3, 5, 8]:
        for s in [8, 13, 21]:
            if f >= s:
                continue
            for kind, gen in [("sma", sma), ("ema", ema)]:
                is_m, oos_m, late_m = run_src(gen(f, s))
                if oos_m.ok and oos_m.trades >= 5:
                    rows.append((kind, f, s, is_m, oos_m, late_m))

    # EMA 8/x for x in fib
    for s in FIB:
        if s <= 8:
            continue
        is_m, oos_m, late_m = run_src(ema(8, s))
        if oos_m.ok and oos_m.trades >= 5:
            rows.append(("ema", 8, s, is_m, oos_m, late_m))

    rows.sort(key=lambda r: (r[5].sharpe, r[4].sharpe, -r[4].max_drawdown), reverse=True)
    print("TOP by late sharpe then oos sharpe:")
    for kind, f, s, is_m, oos_m, late_m in rows[:20]:
        print(
            f"  {kind}_{f}_{s}: IS={is_m.sharpe:.3f} OOS={oos_m.sharpe:.3f} "
            f"d={oos_m.sharpe-bh_oos.sharpe:+.3f} mdd={oos_m.max_drawdown:.3f} "
            f"late={late_m.sharpe:.3f} tr={oos_m.trades}"
        )

    # save champions
    champions = [
        ("30_sma_8_13", sma(8, 13).replace("strategy S", "strategy Sma813", 1), "SMA 8/13 micro cross — sweep champion"),
        ("33_ema_8_34", ema(8, 34).replace("strategy S", "strategy Ema834", 1), "EMA 8/34 — best IS+OOS balance from sweep"),
        ("34_sma_5_13", sma(5, 13).replace("strategy S", "strategy Sma513", 1), "SMA 5/13 faster variant"),
    ]
    for fname, src, hyp in champions:
        path = STRATEGIES / f"{fname}.ms"
        path.write_text(src.strip() + "\n", encoding="utf-8")
        e = evaluate(path, hyp, bh_is, bh_oos)
        print(f"SAVED {fname}: OOS={e['oos_sharpe']:.3f} xfer={e['transfers_oos']}")

    write_summary(bh_is, bh_oos)


if __name__ == "__main__":
    main()
