// Flagship v4 — sophisticated branched exits.
//
//   deepGreen              → late fade / donch34 (IWM hold)
//   path crown (1)         → softCrownExit (QQQ/AMD DNA — never steal)
//   path atr (2) / thrust  → softCrownNoMacd (AAPL DNA)
//   bounce / zero          → short leash
//   fallback               → softCrownExit
//
// Entries: v3 OR-book. Crown latch wins on mixed open bars.

class FlagshipV4 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

  path = new PathLatch()

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
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  thrustingNow = thrust > vol && rising(close, 2)
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  function onBar() {
    when position() == 0: path.clear()

    when bounceSig: {
      when position() == 0: path.set(3)
      long()
    }
    when zeroSig: {
      when position() == 0: path.set(4)
      long()
    }
    when atrSig: {
      when position() == 0: path.set(2)
      long()
    }
    when close > e8 && donchHigh(donchIn): {
      when position() == 0: path.set(1)
      long()
    }

    // Losing crown + ATR signal → borrow AAPL exit sleeve
    when path.is(1) && atrSig && unrealized_pnl < 0: path.set(2)

    // --- exit branches ---
    when deepGreen && bars_in_trade >= 40 && r5 < 45: flat()
    when deepGreen && donchLow(34): flat()

    // Crown sleeve — full soft stack
    when (!deepGreen) && path.is(1) && softCrownExit(midEma): flat()

    // ATR / non-crown thrust — no macdBear
    when (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): flat()

    // Bounce / zero
    when (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): flat()
    when (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): flat()

    // Fallback
    when (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped()
      || ((!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || ((!weakBook) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    )
  }

  function profitLocked() {
    return (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
    )
  }
}

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, momLen, stopPct, timeBars, bullCut, bearCut)
  optimize(sharpe)
}
