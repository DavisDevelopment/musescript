#!/usr/bin/env python3
"""Isolate exit-stack vs entry effects; add IWM late-fade + MSFT macd carefully."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "v2_no_class_extras": """
class FlagshipX extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when softCrownExit(midEma): flat()
  }
}
""",
    "v2_plain_strategy": """
strategy FlagshipPlain {
  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  reg = regimeScore(21)
  onBar {
    when close > e8 && high >= highest(high, 21): long()
    when reg >= 0.28 && thrust > vol && rising(close, 2): long()
    when reg < 0.22 && rising(mf.hist, 3) && close > gate: long()
    when low <= lowest(low, 13) || rsi(close, 13) > 80 || rsi(close, 8) > 82 || m.hist < 0 || close < ema(close, 13): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && falling(r, 3): flat()
  }
}
""",
    "atr_priority_no_crown_if_atr": """
class FlagshipX extends FlagshipRisk {
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param donchIn: Window = 21

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

  function onBar() {
    when atrSig: long()
    // Crown only if ATR path quiet this bar AND not overextended
    when (!atrSig) && close > e8 && donchHigh(donchIn) && r < 72: long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > sma(close, 50): long()
    when softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "v3_iwm_early_hold": """
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

  function onBar() {
    // Seed sticky long early on mild trend (IWM BH proxy)
    when bar_index == 1 && close > open: long()
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // Late fade take-profit (IWM edge)
    when bars_in_trade >= 40 && r5 < 45: flat()
    when softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "v3_dual_sleeve": """
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

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // Bearish flip only when regime weak AND no long signal today
    when reg < bearCut && close < e13 && falling(close, 2) && !(close > e8 && donchHigh(donchIn)): short()
    when position() < 0 && (close > e8 || rising(close, 2) || r < 35): flat()
    when softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && abs(close / entry_price - 1.0) > 0.05)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0 && position() > 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && position() > 0)
  }
}
""",
}


def score(name: str, src: str) -> None:
    tmp = ROOT / "examples/flagship-musescript-module/strategies/probes" / f"_tmp_{name}.ms"
    tmp.write_text(src.strip() + "\n", encoding="utf-8")
    # plain strategy may not need class libs for FlagshipRisk — stitch anyway
    stitched = stitch_source(tmp)
    print(f"\n===== {name} =====")
    for win in ["eval_3m", "wf_2022q1"]:
        n_pass = n = 0
        fails = []
        details = []
        for sym in SYMS:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            n += 1
            m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            if not m.ok:
                fails.append(f"{sym}:ERR")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}")
            if sym in ("IWM", "AAPL", "MSFT"):
                details.append(f"{sym} sh={m.sharpe:+.2f} d={d:+.2f} tr={m.trades} ret={m.total_return:+.1%}")
        print(f"  {win}: {n_pass}/{n}")
        print(f"    targets: {', '.join(details)}")
        if fails:
            print(f"    fails: {fails}")


def main() -> int:
    for name, src in CANDIDATES.items():
        score(name, src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
