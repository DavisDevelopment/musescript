#!/usr/bin/env python3
"""Sticky-bull mode (SMA gate) vs active crown — aim for IWM/AAPL/MSFT without losing 2022."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "sticky50": """
class FlagshipX extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  slow = sma(close, 50)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)
  sticky = close > slow

  function onBar() {
    // Sticky bull: stay long above SMA50 (IWM/AAPL BH proxy)
    when sticky: long()
    // Active sleeve only when not sticky
    when (!sticky) && close > e8 && donchHigh(donchIn): long()
    when (!sticky) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!sticky) && rising(mf.hist, 3) && close > gate: long()
    when (!sticky) && crossover(mz.hist, 0) && close > gate: long()
    // Sticky exit: lost the slow average, or late fade after long hold
    when sticky && close < slow: flat()
    when sticky && bars_in_trade >= 40 && r5 < 45: flat()
    when (!sticky) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!sticky) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!sticky) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!sticky) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "sticky50_atr_boost": """
class FlagshipX extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  slow = sma(close, 50)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)
  sticky = close > slow

  function onBar() {
    when sticky: long()
    // ATR boost even in sticky (AAPL edge) — same direction, more re-entry after fade TP
    when sticky && thrust > vol && rising(close, 2): long()
    when (!sticky) && close > e8 && donchHigh(donchIn): long()
    when (!sticky) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!sticky) && rising(mf.hist, 3) && close > gate: long()
    when (!sticky) && crossover(mz.hist, 0): long()
    when sticky && bars_in_trade >= 40 && r5 < 45: flat()
    when close < slow: flat()
    when (!sticky) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!sticky) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!sticky) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!sticky) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "sticky34_crown_or": """
class FlagshipX extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)
  sticky = close > gate

  function onBar() {
    // Always allow v2 entries
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // Sticky overlay: if above gate and flat, re-enter (fills IWM holes)
    when sticky && position() == 0 && close > e8: long()
    when bars_in_trade >= 40 && r5 < 45: flat()
    // Soft exits suppressed while sticky & green
    when !(sticky && unrealized_pnl > 0) && softCrownExit(midEma): flat()
    when close < gate && roc(close, 3) < -1: flat()
  }

  function hardStopped() {
    return super.hardStopped() || (!(sticky && unrealized_pnl > 0) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (!(sticky && unrealized_pnl > 0) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (!(sticky && unrealized_pnl > 0) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "near_bh_sma50_only": """
strategy NearBh {
  e = sma(close, 50)
  r5 = rsi(close, 5)
  onBar {
    when close > e: long()
    when close < e: flat()
    when bars_in_trade >= 40 && r5 < 45: flat()
  }
}
""",
}


def score(name: str, src: str) -> None:
    tmp = ROOT / "examples/flagship-musescript-module/strategies/probes" / f"_tmp_{name}.ms"
    tmp.write_text(src.strip() + "\n", encoding="utf-8")
    stitched = stitch_source(tmp)
    print(f"\n===== {name} =====")
    for win in ["eval_3m", "wf_2022q1"]:
        n_pass = n = 0
        fails = []
        details = []
        for sym in SYMS:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            n += 1
            if not m.ok:
                fails.append(f"{sym}:ERR:{m.error[:60]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}/sh={m.sharpe:+.2f}/ret={m.total_return:+.1%}")
            if sym in ("IWM", "AAPL", "MSFT", "SPY", "QQQ", "NVDA"):
                details.append(
                    f"{sym} sh={m.sharpe:+.2f} d={d:+.2f} tr={m.trades} ret={m.total_return:+.1%}"
                )
        print(f"  {win}: {n_pass}/{n}")
        print(f"    key: {', '.join(details)}")
        print(f"    fails: {fails}")


def main() -> int:
    for name, src in CANDIDATES.items():
        score(name, src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
