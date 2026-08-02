#!/usr/bin/env python3
"""Trend-split playbooks: strong-trend hold vs weak-tape MACD/short vs medium crown."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "split_roc55": """
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
  trend = roc(close, 55)
  strong = trend > 4
  weak = trend < -2

  function onBar() {
    // Strong tape: seed + hold (IWM/AAPL BH edge), late fade TP
    when strong && position() == 0: long()
    when strong && bars_in_trade >= 40 && r5 < 45: flat()
    when strong && close < gate && roc(close, 5) < -4: flat()

    // Weak tape: MSFT playbook
    when weak && crossover(mz.hist, 0): long()
    when weak && close < e13 && falling(close, 2): short()
    when weak && position() > 0 && (bars_in_trade >= 13 || mz.hist < 0): flat()
    when weak && position() < 0 && (close > e8 || bars_in_trade >= 8 || r < 35): flat()

    // Medium tape: classic v2 crown/ATR/MACD
    when (!strong) && (!weak) && close > e8 && donchHigh(donchIn): long()
    when (!strong) && (!weak) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!strong) && (!weak) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!strong) && (!weak) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!strong) && bars_in_trade >= 5 && close < e13 && position() > 0)
  }

  function timedOut() {
    return super.timedOut() || ((!strong) && bars_in_trade >= 8 && close < e34 && m.hist < 0 && position() > 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!strong) && bars_in_trade >= 5 && falling(r, 3) && position() > 0)
  }
}
""",
    "split_roc21": """
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
  trend = roc(close, 21)
  strong = trend > 3
  weak = trend < -1

  function onBar() {
    when strong && position() == 0 && close > e8: long()
    when strong && bars_in_trade >= 34 && r5 < 45: flat()
    when strong && roc(close, 5) < -5: flat()

    when weak && crossover(mz.hist, 0): long()
    when weak && close < e13 && falling(close, 2): short()
    when weak && position() > 0 && (bars_in_trade >= 13 || softCrownExit(midEma)): flat()
    when weak && position() < 0 && (close > e8 || bars_in_trade >= 8): flat()

    when (!strong) && (!weak) && close > e8 && donchHigh(donchIn): long()
    when (!strong) && (!weak) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!strong) && (!weak) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!strong) && (!weak) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!strong) && position() > 0 && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!strong) && position() > 0 && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!strong) && position() > 0 && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "hold_then_fade": """
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
    // Prefer one primary entry early; allow ATR add only
    when bar_index == 1: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // NO soft crown — only fade / crash / class risk
    when bars_in_trade >= 40 && r5 < 45: flat()
    when close < gate && roc(close, 5) < -3: flat()
    when rsi(close, 13) > 85: flat()
  }

  function hardStopped() {
    return super.hardStopped()
  }

  function timedOut() {
    return false
  }

  function profitLocked() {
    return bars_in_trade >= 40 && falling(r5, 3)
  }
}
""",
    "v2_plus_iwm_fade_only": """
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
    when bar_index == 1: long()
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // If we've been in a long time from bar-1 seed, prefer fade over soft crown
    when bars_in_trade >= 40 && r5 < 45: flat()
    when bars_in_trade < 40 && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13 && bars_in_trade < 40)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0 && bars_in_trade < 40)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && bars_in_trade < 40)
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
