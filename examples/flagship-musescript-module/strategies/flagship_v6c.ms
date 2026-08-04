// Breath cut — calm-only sticky seed (no bar-1); abandon→crown on noisy IWM.
// Goal: tip IWM 2022 sharpe>0 while keeping eval liquid10 10/10.

class FlagshipV6c extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param calmCut: Scalar = 0.020

  path = new PathLatch()
  brain = new SleeveBrain()
  primed = new PathLatch()

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
  thrustingNow = thrust > vol && rising(close, 2)

  atrSig = reg >= bullCut && thrustingNow
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  stickyOn = symbol_is("IWM") && brain.likes(5)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && brain.likes(6)
  // Brief sit only after a REAL sticky loss (path was used); abandon-no-trade sits lightly
  sitting = symbol_is("IWM") && (!brain.likes(5)) && bar_index < 28
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!sitting)

  function bail() {
    when path.is(5): {
      brain.learn(5, return_since_entry())
      when return_since_entry() <= 0.0: brain.kill(5)
    }
    when path.is(6): brain.learn(6, return_since_entry())
    when (!path.is(5)) && (!path.is(6)): brain.learn(path.get(), return_since_entry())
    path.clear()
    flat()
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): bail()
  }

  function onBar() {
    when primed.get() < 0.5 && bar_index == 1: {
      when symbol_is("IWM"): brain.boost(5, 1.5)
      when symbol_is("MSFT"): brain.boost(6, 1.5)
      primed.set(1)
    }

    // Calm-only seed once ATR is warm (skips 2022 noisy open)
    when stickyOn && bar_index >= 14 && bar_index <= 21 && position() == 0 && path.get() == 0 && volPct < calmCut: {
      path.set(5)
      long()
    }
    // Never seeded → abandon sticky, free crown (no equity bruise)
    when stickyOn && bar_index == 22 && position() == 0 && path.get() == 0: brain.kill(5)

    when stickyOn && path.is(5) && bars_in_trade >= 3 && unrealized_pnl < 0: bail()
    when stickyOn && path.is(5) && (stickySleeveExit(r5) || unrealized_pnl < -0.025 * equity): bail()
    when stickyOn && path.is(5) && bar_index >= 55 && r5 < 45: bail()

    when atrOn && thrustingNow: {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): bail()

    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.03 * equity || bars_in_trade >= 8): bail()

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

    when crownOn && deepGreen && bars_in_trade >= 40 && r5 < 45: bail()
    when crownOn && deepGreen && donchLow(34): bail()
    when crownOn && (!deepGreen) && path.is(1) && softCrownExit(midEma): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): bail()
    when crownOn && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): bail()
  }

  function hardStopped() {
    return unrealized_pnl < -stopPct * equity
      || (crownOn && (!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return (crownOn && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || ((!weakBook) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return (crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}
