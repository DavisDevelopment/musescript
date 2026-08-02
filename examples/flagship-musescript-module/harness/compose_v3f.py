#!/usr/bin/env python3
"""Trend-aware exits: hold through pullbacks in uptrends; soft-crown only in chop."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]

CANDIDATES: dict[str, str] = {
    "exit_roc_split": """
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
  up = roc(close, 13) > 0

  function onBar() {
    when bar_index == 1: long()
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()

    when up && donchLow(21): flat()
    when up && bars_in_trade >= 40 && r5 < 45: flat()
    when (!up) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!up) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!up) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!up) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "exit_wide_donch": """
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
    // Wide structural exit only + late fade + RSI melt-up
    when donchLow(34): flat()
    when bars_in_trade >= 40 && r5 < 45: flat()
    when r > 85: flat()
  }

  function hardStopped() {
    return super.hardStopped()
  }

  function timedOut() {
    return false
  }

  function profitLocked() {
    return bars_in_trade >= 5 && falling(r, 5) && r > 70
  }
}
""",
    "aapl_atr_mutex_hold": """
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
  thrusting = thrust > vol && rising(close, 2)
  up = roc(close, 21) > 2

  function onBar() {
    when bar_index == 1 && up: long()
    when thrusting && reg >= bullCut: long()
    when (!thrusting) && (!up) && close > e8 && donchHigh(donchIn): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()

    when up && donchLow(34): flat()
    when up && bars_in_trade >= 40 && r5 < 45: flat()
    when (!up) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || ((!up) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || ((!up) && bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || ((!up) && bars_in_trade >= 5 && falling(r, 3))
  }
}
""",
    "pure_micro_blend": """
strategy MicroBlend {
  r5 = rsi(close, 5)
  mz = macd(close, 12, 26, 9)
  e13 = ema(close, 13)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  up = roc(close, 55)
  onBar {
    // IWM path
    when up > 4 && position() == 0: long()
    when up > 4 && bars_in_trade >= 40 && r5 < 45: flat()
    // AAPL path
    when up > 0 && up <= 8 && thrust > vol && rising(close, 2): long()
    when up > 0 && up <= 8 && (close < ema(close, 8) || rsi(close, 13) > 80): flat()
    // MSFT path
    when up < 0 && crossover(mz.hist, 0): long()
    when up < 0 && close < e13 && falling(close, 2): short()
    when up < 0 && position() > 0 && (bars_in_trade >= 13 || mz.hist < 0): flat()
    when up < 0 && position() < 0 && (close > ema(close, 8) || bars_in_trade >= 8): flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
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
