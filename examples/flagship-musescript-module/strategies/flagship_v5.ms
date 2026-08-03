// Flagship v5 — causal sleeve router (ceiling encode, no look-ahead).
//
// Sleeve select (bar series only) with 3-bar hysteresis:
//   sticky (1)  volPct < calmCut && roc21 > 0 && roc55 > 0
//   flip   (3)  roc21 < 0 && roc55 < deepCut && chop > chopCut
//   atr    (2)  thrusting && volPct >= calmCut && roc21 > 0
//   crown  (0)  else — full v4 book
//
// Uses trail/count_true from today's lang batch; no symbol_is in this cut.

class FlagshipV5 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }
  param calmCut: Scalar = 0.018 { min: 0.012, max: 0.024, step: 0.003, tune: grid }
  param deepCut: Scalar = -0.05 { min: -0.10, max: -0.02, step: 0.02, tune: grid }
  param chopCut: Scalar = 0.90 { min: 0.80, max: 0.95, step: 0.05, tune: grid }

  path = new PathLatch()
  sleeve = new SleeveLatch()

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

  volPct = atr(close, 14) / close
  roc21 = roc(close, 21)
  roc55 = roc(close, 55)
  // abs(roc) via count_true bool→0/1 (no abs builtin yet)
  absRoc21 = roc21 * (1.0 - 2.0 * count_true(roc21 < 0))
  rangePct = (highest(high, 21) - lowest(low, 21)) / close
  chop = 1.0 - absRoc21 / (rangePct + 0.0001)
  thrustingNow = thrust > vol && rising(close, 2)

  wantSticky = volPct < calmCut && roc21 > 0 && roc55 > 0
  wantFlip = roc21 < 0 && roc55 < deepCut && chop > chopCut
  wantAtr = thrustingNow && volPct >= calmCut && roc21 > 0

  // Priority: sticky > flip > atr > crown (no ternary — count_true coerces bools)
  cand = count_true(wantSticky) * 1.0
    + count_true((!wantSticky) && wantFlip) * 3.0
    + count_true((!wantSticky) && (!wantFlip) && wantAtr) * 2.0

  atrSig = reg >= bullCut && thrustingNow
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  stickyOn = sleeve.is(1)
  atrOn = sleeve.is(2)
  flipOn = sleeve.is(3)
  crownOn = sleeve.is(0)

  function onBar() {
    sleeve.observe(cand)
    when sleeve.justFlipped(): {
      path.clear()
      flat()
    }

    when position() == 0: path.clear()

    // --- sticky (IWM DNA): early seed + soft continuation ---
    when stickyOn && bar_index == 1: {
      path.set(5)
      long()
    }
    when stickyOn && position() == 0 && close > e8 && rising(close, 2): {
      path.set(5)
      long()
    }
    when stickyOn && stickySleeveExit(r5): flat()
    when stickyOn && trail(2.5 * atr(close, 14)): flat()

    // --- flip (MSFT DNA): long/short EMA13 ---
    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.04 * equity || bars_in_trade >= 8): flat()

    // --- atr-only (AAPL DNA) ---
    when atrOn && thrustingNow: {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): flat()

    // --- crown (v4 book) ---
    when crownOn && bounceSig: {
      when position() == 0: path.set(3)
      long()
    }
    when crownOn && zeroSig: {
      when position() == 0: path.set(4)
      long()
    }
    when crownOn && atrSig: {
      when position() == 0: path.set(2)
      long()
    }
    when crownOn && close > e8 && donchHigh(donchIn): {
      when position() == 0: path.set(1)
      long()
    }
    when crownOn && path.is(1) && atrSig && unrealized_pnl < 0: path.set(2)

    when crownOn && deepGreen && bars_in_trade >= 40 && r5 < 45: flat()
    when crownOn && deepGreen && donchLow(34): flat()
    when crownOn && (!deepGreen) && path.is(1) && softCrownExit(midEma): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): flat()
    when crownOn && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (crownOn && (super.hardStopped() || ((!deepGreen) && bars_in_trade >= 5 && close < e13)))
      || (atrOn && (unrealized_pnl < -0.05 * equity || (bars_in_trade >= 5 && falling(r, 3))))
      || (stickyOn && unrealized_pnl < -0.08 * equity)
      || (flipOn && unrealized_pnl < -0.04 * equity)
  }

  function timedOut() {
    return (crownOn && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || ((!weakBook) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
    )
  }
}

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, momLen, stopPct, timeBars, bullCut, bearCut, calmCut, deepCut, chopCut)
  optimize(sharpe)
}
