#!/usr/bin/env python3
"""Hunt sticky-long / dip-hold families that can beat strong BH (IWM) and rescue MSFT/AAPL."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import RESULTS, run_gene, rel  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

FAMILIES: dict[str, str] = {
    "near_bh_crash": """
strategy NearBhCrash {
  onBar {
    when bar_index == 1: long()
    when close < sma(close, 50) && roc(close, 5) < -3: flat()
    when close > sma(close, 21) && position == 0: long()
  }
}
""",
    "near_bh_sma200": """
strategy NearBhSma200 {
  e = sma(close, 200)
  onBar {
    when close > e: long()
    when close < e: flat()
  }
}
""",
    "near_bh_sma50": """
strategy NearBhSma50 {
  e = sma(close, 50)
  onBar {
    when close > e: long()
    when close < e: flat()
  }
}
""",
    "dip_ema21": """
strategy DipEma21 {
  e = ema(close, 21)
  gate = sma(close, 50)
  r = rsi(close, 2)
  onBar {
    when close > gate && close < e && r < 30: long()
    when close > e * 1.02 || rsi(close, 13) > 75: flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
""",
    "pullback_ema8": """
strategy PullbackEma8 {
  e8 = ema(close, 8)
  e34 = ema(close, 34)
  onBar {
    when close > e34 && crossunder(close, e8): long()
    when close < e34 || rsi(close, 13) > 78: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
""",
    "sticky_donch": """
strategy StickyDonch {
  e8 = ema(close, 8)
  onBar {
    when close > e8 && high >= highest(high, 55): long()
    when close < sma(close, 55): flat()
  }
  onPosition {
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
""",
    "sticky_crown": """
strategy StickyCrown {
  e8 = ema(close, 8)
  e55 = ema(close, 55)
  onBar {
    when close > e8 && high >= highest(high, 21): long()
    when close < e55: flat()
  }
  onPosition {
    when unrealized_pnl < -0.08 * equity: flat()
    when bars_in_trade >= 34 && falling(rsi(close, 13), 5): flat()
  }
}
""",
    "atr_mutex_soft": """
strategy AtrMutexSoft {
  e8 = ema(close, 8)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  thrusting = thrust > vol && rising(close, 2)
  onBar {
    when thrusting: long()
    when (!thrusting) && close > e8 && high >= highest(high, 21) && rsi(close, 13) < 70: long()
    when close < e8 || rsi(close, 13) > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && falling(rsi(close, 13), 3): flat()
  }
}
""",
    "crown_rsi_cap": """
strategy CrownRsiCap {
  e8 = ema(close, 8)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  r = rsi(close, 13)
  onBar {
    when close > e8 && high >= highest(high, 21) && r < 65: long()
    when thrust > vol && rising(close, 2): long()
    when close < e8 || r > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && falling(r, 3): flat()
  }
}
""",
    "msft_macd_bounce_free": """
strategy MacdBounceFree {
  mf = macd(close, 8, 21, 5)
  gate = sma(close, 34)
  e13 = ema(close, 13)
  onBar {
    when rising(mf.hist, 3) && close > gate: long()
    when close < e13 || mf.hist < 0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "dual_timeframe": """
strategy DualTf {
  fast = ema(close, 8)
  slow = ema(close, 34)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when close > slow && thrust > vol && rising(close, 2): long()
    when close > slow && close > fast && high >= highest(high, 34): long()
    when close < slow: flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
""",
    "stoch_os": """
strategy StochOs {
  s = stoch(14, 3, 3)
  gate = sma(close, 50)
  onBar {
    when close > gate && s.k < 20 && crossover(s.k, s.d): long()
    when s.k > 80 || close < gate: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
}


def passes(m, bh) -> bool:
    if not m.ok or not bh.ok:
        return False
    d = m.sharpe - bh.sharpe
    return m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25


def main() -> int:
    targets = ["MSFT", "IWM", "AAPL"]
    controls = ["SPY", "QQQ", "NVDA", "AMD", "AMZN", "GOOGL", "META", "TSLA"]
    rows = []
    print(f"{'fam':22} {'sym':5} {'win':10} {'sharpe':8} {'dBH':8} {'tr':4} {'ret':9} mark")
    for win in ["eval_3m", "wf_2022q1"]:
        for sym in targets + controls:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            for name, src in FAMILIES.items():
                m = run_gene(src, tape, execution="next-open", cost_bps=10)
                if not m.ok:
                    if sym == "MSFT" and win == "eval_3m":
                        print(f"{name:22} FAIL: {m.error[:100]}")
                    continue
                d = m.sharpe - bh.sharpe if bh.ok else float("nan")
                ok = passes(m, bh)
                mark = "PASS" if ok else "weak"
                if sym in targets or (ok and win == "eval_3m"):
                    print(
                        f"{name:22} {sym:5} {win:10} {m.sharpe:+8.3f} {d:+8.3f} "
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

    print("\n=== TARGET PASSES ===")
    for r in rows:
        if r["target"] and r["pass"]:
            print(
                f"  {r['family']:22} {r['symbol']:5} {r['window']:10} "
                f"dBH={r['d_sharpe']:+.3f} sharpe={r['sharpe']:+.3f} ret={r['ret']:+.2%}"
            )

    print("\n=== FAMILY SCORECARD (eval_3m) ===")
    for fam in FAMILIES:
        tgt = [r for r in rows if r["family"] == fam and r["window"] == "eval_3m" and r["target"]]
        ctrl = [r for r in rows if r["family"] == fam and r["window"] == "eval_3m" and not r["target"]]
        wf = [r for r in rows if r["family"] == fam and r["window"] == "wf_2022q1"]
        print(
            f"  {fam:22} tgt={sum(r['pass'] for r in tgt)}/{len(tgt)} "
            f"ctrl={sum(r['pass'] for r in ctrl)}/{len(ctrl)} "
            f"wf={sum(r['pass'] for r in wf)}/{len(wf)}"
        )

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / "sticky_hunt.json"
    out.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"\nwrote {rel(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
