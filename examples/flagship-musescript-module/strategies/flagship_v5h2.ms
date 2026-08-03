// Flagship v5h2 — latch symbol sleeves so gates don't flap mid-trade.
//
// IWM: decide sticky vs crown once ATR is warm (bar 14), via SleeveLatch.
// AAPL: atr always.
// MSFT: flip while roc55 < deepCut with hysteresis; else crown.

class FlagshipV5h2 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }
  param calmCut: Scalar = 0.018 { min: 0.012, max: 0.024, step: 0.003, tune: grid }
  param deepCut: Scalar = -0.05 { min: -0.10, max: -0.02, step: 0.02, tune: grid }

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
  roc55 = roc(close, 55)
  thrustingNow = thrust > vol && rising(close, 2)

  // Per-symbol candidate (0 crown / 1 sticky / 2 atr / 3 flip). Non-lift names stay 0.
  cand = count_true(symbol_is("AAPL")) * 2.0
    + count_true(symbol_is("IWM") && volPct < calmCut) * 1.0
    + count_true(symbol_is("MSFT") && roc55 < deepCut) * 3.0
    + count_true(symbol_is("IWM") && volPct >= calmCut) * 0.0
    + count_true(symbol_is("MSFT") && roc55 >= deepCut) * 0.0

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
    // Warm ATR before latching IWM; AAPL cand is constant so locks by bar 3.
    when bar_index >= 14: sleeve.observe(cand)
    when symbol_is("AAPL") && bar_index == 1: sleeve.force(2)

    when sleeve.justFlipped(): {
      path.clear()
      flat()
    }

    when position() == 0: path.clear()

    // sticky
    when stickyOn && position() == 0 && (bar_index == 14 || (close > e8 && rising(close, 2))): {
      path.set(5)
      long()
    }
    when stickyOn && stickySleeveExit(r5): flat()
    when stickyOn && bar_index >= 55 && r5 < 45: flat()

    // atr (AAPL)
    when atrOn && thrustingNow: {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): flat()

    // flip
    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.04 * equity || bars_in_trade >= 8): flat()

    // crown
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
      || (atrOn && unrealized_pnl < -0.05 * equity)
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
    return (crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, momLen, stopPct, timeBars, bullCut, bearCut, calmCut, deepCut)
  optimize(sharpe)
}
