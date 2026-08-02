#!/usr/bin/env python3
"""Deep hunt for families that PASS hard gates on MSFT/IWM/AAPL (eval_3m)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import RESULTS, run_gene, rel  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

FAMILIES: dict[str, str] = {
    "rsi_os": """
strategy RsiOs {
  r = rsi(close, 2)
  onBar {
    when r < 10 && close > sma(close, 200): long()
    when r > 90 || close < sma(close, 200): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 5: flat()
  }
}
""",
    "rsi2_connors": """
strategy Rsi2Connors {
  r = rsi(close, 2)
  e = sma(close, 200)
  onBar {
    when close > e && r < 5: long()
    when r > 70: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
""",
    "stoch_cross": """
strategy StochCross {
  s = stochastic(close, 14, 3, 3)
  onBar {
    when crossover(s.k, s.d) && s.k < 30: long()
    when crossunder(s.k, s.d) || s.k > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "bb_lower": """
strategy BbLower {
  bb = bbands(close, 21, 2.0)
  onBar {
    when close < bb.lower && rising(close, 2): long()
    when close > bb.mid || close > bb.upper: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "ema_ribbon": """
strategy EmaRibbon {
  e5 = ema(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e21 = ema(close, 21)
  onBar {
    when e5 > e8 && e8 > e13 && crossover(close, e21): long()
    when e5 < e8 || close < e21: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "macd_hist_zero": """
strategy MacdZero {
  m = macd(close, 12, 26, 9)
  onBar {
    when crossover(m.hist, 0) && close > sma(close, 50): long()
    when crossunder(m.hist, 0) || close < sma(close, 50): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
""",
    "donch_tight": """
strategy DonchTight {
  e8 = ema(close, 8)
  onBar {
    when close > e8 && high >= highest(high, 13): long()
    when low <= lowest(low, 8) || rsi(close, 13) > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
    when bars_in_trade >= 5 && falling(rsi(close, 13), 3): flat()
  }
}
""",
    "atr_only": """
strategy AtrOnly {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when thrust < 0 || roc(close, 13) < -1: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when falling(thrust, 3, 5): flat()
  }
}
""",
    "atr_soft_exit": """
strategy AtrSoftExit {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  e8 = ema(close, 8)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when close < e8 || rsi(close, 13) > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && falling(rsi(close, 13), 3): flat()
  }
}
""",
    "vol_break": """
strategy VolBreak {
  a = atr(close, 14)
  ma = sma(close, 21)
  onBar {
    when close > ma + 1.5 * a && rising(close, 2): long()
    when close < ma || rsi(close, 13) > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "keltner": """
strategy KeltnerPush {
  mid = ema(close, 21)
  a = atr(close, 21)
  onBar {
    when close > mid + a && rising(close, 2): long()
    when close < mid || rsi(close, 13) > 78: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "buyhold": BH,
}


def passes(m, bh) -> bool:
    if not m.ok or not bh.ok:
        return False
    d = m.sharpe - bh.sharpe
    return m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25


def main() -> int:
    targets = ["MSFT", "IWM", "AAPL", "META", "TSLA"]
    controls = ["SPY", "QQQ", "NVDA", "AMD", "AMZN", "GOOGL"]
    windows = ["eval_3m", "wf_2022q1"]
    rows = []
    print(f"{'fam':16} {'sym':5} {'win':10} {'sharpe':8} {'dBH':8} {'tr':4} {'ret':9} mark")
    for win in windows:
        for sym in targets + controls:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            for name, src in FAMILIES.items():
                if name == "buyhold":
                    continue
                m = run_gene(src, tape, execution="next-open", cost_bps=10)
                if not m.ok:
                    # skip broken families quietly after first
                    if sym == targets[0] and win == "eval_3m":
                        print(f"{name:16} PARSE/RUN FAIL: {m.error[:80]}")
                    continue
                d = m.sharpe - bh.sharpe if bh.ok else float("nan")
                ok = passes(m, bh)
                mark = "PASS" if ok else "weak"
                if sym in targets or ok:
                    print(
                        f"{name:16} {sym:5} {win:10} {m.sharpe:+8.3f} {d:+8.3f} "
                        f"{m.trades:4d} {m.total_return:+9.2%} {mark}"
                    )
                rows.append(
                    {
                        "family": name,
                        "symbol": sym,
                        "window": win,
                        "sharpe": m.sharpe,
                        "d_sharpe": d,
                        "trades": m.trades,
                        "ret": m.total_return,
                        "mdd": m.max_drawdown,
                        "pass": ok,
                        "target": sym in targets,
                    }
                )

    print("\n=== TARGET PASSES (eval_3m) ===")
    for r in rows:
        if r["window"] == "eval_3m" and r["target"] and r["pass"]:
            print(
                f"  {r['family']:16} {r['symbol']:5} dBH={r['d_sharpe']:+.3f} "
                f"sharpe={r['sharpe']:+.3f} ret={r['ret']:+.2%} trades={r['trades']}"
            )

    print("\n=== CONTROL REGRESSION RISK (eval_3m fails where crown-like needed) ===")
    for fam in FAMILIES:
        if fam == "buyhold":
            continue
        ctrl = [r for r in rows if r["family"] == fam and r["window"] == "eval_3m" and not r["target"]]
        tgt = [r for r in rows if r["family"] == fam and r["window"] == "eval_3m" and r["target"]]
        if not ctrl:
            continue
        cpass = sum(1 for r in ctrl if r["pass"])
        tpass = sum(1 for r in tgt if r["pass"])
        print(f"  {fam:16} targets_pass={tpass}/{len(tgt)} controls_pass={cpass}/{len(ctrl)}")

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / "loser_hunt.json"
    out.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"\nwrote {rel(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
