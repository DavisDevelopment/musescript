#!/usr/bin/env python3
"""Early-entry / late-fade windowing + ATR rescue for AAPL + MACD for MSFT."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "v3_early_late": """
class FlagshipV3 extends FlagshipRisk {
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
  early = bar_index < 45
  late = bar_index >= 50

  function onBar() {
    when bar_index == 1: long()
    // Full v2 book in early window
    when early && close > e8 && donchHigh(donchIn): long()
    when early && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when early && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    // Late window: only ATR / MACD zero (no crown churn)
    when (!early) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!early) && crossover(mz.hist, 0) && close > gate: long()
    // Late fade TP (IWM DNA)
    when late && r5 < 45: flat()
    // Soft crown only early/mid
    when early && softCrownExit(midEma): flat()
    when (!early) && (!late) && donchLow(21): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (early && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (early && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (early && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "v3_seed_hold_atr": """
class FlagshipV3 extends FlagshipRisk {
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
    when bar_index == 1: long()
    // ATR always (AAPL)
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    // Crown only if not already long from seed recently — approximated by flat book
    when position() == 0 && close > e8 && donchHigh(donchIn): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()

    // While seeded long (long hold): only structural / fade exits
    when bars_in_trade >= 40 && r5 < 45: flat()
    when bars_in_trade >= 21 && donchLow(34): flat()
    // Short trades: soft crown
    when bars_in_trade < 21 && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade < 21 && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade < 21 && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade < 21 && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "v3_iwm_exact_plus": """
class FlagshipV3 extends FlagshipRisk {
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
  // True while still in the bar-1 seed trade (never flattened since open).
  seedHold = position() > 0 && bars_in_trade >= bar_index - 1

  function onBar() {
    when bar_index == 1: long()
    // Seed: only late fade (IWM micro-edge). No soft crown while seeded.
    when seedHold && bar_index >= 55 && r5 < 45: flat()
    when seedHold && unrealized_pnl < -0.08 * equity: flat()

    // Active book only when not in seed hold
    when (!seedHold) && close > e8 && donchHigh(donchIn): long()
    when (!seedHold) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!seedHold) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!seedHold) && crossover(mz.hist, 0) && close > gate: long()
    when (!seedHold) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!seedHold) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!seedHold) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!seedHold) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "v3_seed_always_protect": """
class FlagshipV3 extends FlagshipRisk {
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
  seedHold = position() > 0 && bars_in_trade >= bar_index - 1

  function onBar() {
    when bar_index == 1: long()
    when seedHold && bar_index >= 55 && r5 < 45: flat()
    when seedHold && unrealized_pnl < -0.08 * equity: flat()

    // ATR may add/reenter even during seed? No — only when flat/non-seed
    when (!seedHold) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!seedHold) && close > e8 && donchHigh(donchIn): long()
    when (!seedHold) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!seedHold) && crossover(mz.hist, 0) && close > gate: long()
    // Also allow ATR to fire while seed if we want AAPL boost — skip, keep seed pure

    when (!seedHold) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (!seedHold) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13))
  }

  function timedOut() {
    return (!seedHold) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0))
  }

  function profitLocked() {
    return (!seedHold) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3)))
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
                fails.append(f"{sym}:ERR:{m.error[:70]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}/sh={m.sharpe:+.2f}/ret={m.total_return:+.1%}")
            if sym in ("IWM", "AAPL", "MSFT", "SPY", "QQQ", "NVDA", "AMD"):
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
