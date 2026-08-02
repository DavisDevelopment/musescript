#!/usr/bin/env python3
"""Surgical probes: soft-exit suppression (IWM) + crown extension filters (AAPL) + MSFT macd."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "soft_suppress_green": """
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
  deepGreen = bars_in_trade >= 13 && unrealized_pnl > 0.02 * equity

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    when bars_in_trade >= 40 && r5 < 45: flat()
    when (!deepGreen) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13 && !deepGreen)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0 && !deepGreen)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && !deepGreen)
  }
}
""",
    "crown_not_extended": """
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
  mid = sma(close, 21)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)
  deepGreen = bars_in_trade >= 13 && unrealized_pnl > 0.02 * equity

  function onBar() {
    // Crown only when breakout is not already stretched vs mid
    when close > e8 && donchHigh(donchIn) && close < mid + 1.5 * vol: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    when bars_in_trade >= 40 && r5 < 45: flat()
    when (!deepGreen) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13 && !deepGreen)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0 && !deepGreen)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && !deepGreen)
  }
}
""",
    "atr_first_crown_vol": """
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
  atrSig = reg >= bullCut && thrust > vol && rising(close, 2)
  deepGreen = bars_in_trade >= 13 && unrealized_pnl > 0.02 * equity

  function onBar() {
    when atrSig: long()
    // Crown when ATR quiet AND vol expansion day (range wide)
    when (!atrSig) && close > e8 && donchHigh(donchIn) && (high - low) > vol: long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    when bars_in_trade >= 40 && r5 < 45: flat()
    when (!deepGreen) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13 && !deepGreen)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0 && !deepGreen)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && !deepGreen)
  }
}
""",
    "bh_seed_plus_v2": """
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
  deepGreen = bars_in_trade >= 21 && unrealized_pnl > 0.03 * equity

  function onBar() {
    when bar_index == 1: long()
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // Only hard crash exits while deep green; late fade TP
    when deepGreen && close < sma(close, 50) && roc(close, 5) < -3: flat()
    when bars_in_trade >= 40 && r5 < 45: flat()
    when (!deepGreen) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!deepGreen) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!deepGreen) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "msft_short_weak": """
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
  deepGreen = bars_in_trade >= 13 && unrealized_pnl > 0.02 * equity

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    when reg < bearCut && close < e13 && falling(close, 2): short()
    when position() < 0 && (close > e8 || r < 35 || bars_in_trade >= 8): flat()
    when bars_in_trade >= 40 && r5 < 45 && position() > 0: flat()
    when (!deepGreen) && position() > 0 && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (position() > 0 && bars_in_trade >= 5 && close < e13 && !deepGreen)
  }

  function timedOut() {
    return super.timedOut() || (position() > 0 && bars_in_trade >= 8 && close < e34 && m.hist < 0 && !deepGreen)
  }

  function profitLocked() {
    return super.profitLocked() || (position() > 0 && bars_in_trade >= 5 && falling(r, 3) && !deepGreen)
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
                fails.append(f"{sym}:ERR:{m.error[:50]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}/sh={m.sharpe:+.2f}")
            if sym in ("IWM", "AAPL", "MSFT", "SPY", "QQQ"):
                details.append(f"{sym} sh={m.sharpe:+.2f} d={d:+.2f} tr={m.trades} ret={m.total_return:+.1%}")
        print(f"  {win}: {n_pass}/{n}")
        print(f"    key: {', '.join(details)}")
        if fails:
            print(f"    fails: {fails}")


def main() -> int:
    for name, src in CANDIDATES.items():
        score(name, src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
