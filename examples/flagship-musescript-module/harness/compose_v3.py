#!/usr/bin/env python3
"""Compose candidate v3 DNA and score liquid10 × eval_3m + wf_2022q1."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import LIB, run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

# Candidates written as full class bodies (libs stitched via temp files).
CANDIDATES: dict[str, str] = {
    "v2_base": (ROOT / "examples/flagship-musescript-module/strategies/flagship_v2.ms").read_text(
        encoding="utf-8"
    ),
    "v3a_rsi_cap": """
class FlagshipV3a extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

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
    when close > e8 && donchHigh(donchIn) && r < 65: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
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
    "v3b_fade_tp": """
class FlagshipV3b extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

  r = rsi(close, 13)
  r5 = rsi(close, 5)
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
    when close > e8 && donchHigh(donchIn) && r < 65: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    // IWM DNA: lock gains after long sticky hold when short RSI fades
    when bars_in_trade >= 34 && unrealized_pnl > 0.03 * equity && r5 < 45: flat()
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
    "v3c_macd_free": """
class FlagshipV3c extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

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
    when close > e8 && donchHigh(donchIn) && r < 65: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    // MSFT DNA: classic MACD hist zero-cross (ungated, rare)
    when crossover(mz.hist, 0) && close > gate: long()
    when bars_in_trade >= 34 && unrealized_pnl > 0.03 * equity && r5 < 45: flat()
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
    "v3d_flip_bear": """
class FlagshipV3d extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

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
    when close > e8 && donchHigh(donchIn) && r < 65: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // MSFT DNA: short only in weak regime
    when reg < bearCut && close < e13 && falling(close, 2): short()
    when bars_in_trade >= 34 && unrealized_pnl > 0.03 * equity && r5 < 45: flat()
    when softCrownExit(midEma): flat()
    when position() < 0 && (close > e13 || r < 30): flat()
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
    "v3e_sticky_reentry": """
class FlagshipV3e extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

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
    // Early sticky: first viable trend push holds longer via softer exits below
    when close > e8 && donchHigh(donchIn) && r < 65: long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()
    // Prefer fade-TP over soft crown when deeply green (IWM)
    when bars_in_trade >= 34 && unrealized_pnl > 0.03 * equity && r5 < 45: flat()
    // Soft crown only if not in deep green sticky hold
    when !(bars_in_trade >= 21 && unrealized_pnl > 0.04 * equity) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3) && unrealized_pnl < 0.04 * equity)
  }
}
""",
}


def score(name: str, src: str) -> None:
    # Write temp strategy and stitch libs
    tmp = ROOT / "examples/flagship-musescript-module/strategies/probes" / f"_tmp_{name}.ms"
    tmp.write_text(src.strip() + "\n", encoding="utf-8")
    stitched = stitch_source(tmp)
    print(f"\n===== {name} =====")
    for win in ["eval_3m", "wf_2022q1"]:
        n_pass = 0
        n = 0
        fails = []
        for sym in ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            n += 1
            m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            if not m.ok:
                fails.append(f"{sym}:ERR:{m.error[:40]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
            else:
                fails.append(f"{sym}:sh={m.sharpe:+.2f}/d={d:+.2f}/tr={m.trades}/ret={m.total_return:+.1%}")
        print(f"  {win}: {n_pass}/{n}  fails={fails}")


def main() -> int:
    for name, src in CANDIDATES.items():
        score(name, src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
