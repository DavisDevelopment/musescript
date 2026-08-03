// Probe: IWM always-seed with bear kill; AAPL atr; MSFT ungated flip with early abort; else v4.

class ProbeV5IwmKill extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

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

  stickyOn = symbol_is("IWM")
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT")
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn)

  atrSig = reg >= bullCut && thrust > vol && rising(close, 2)
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  thrustingNow = thrust > vol && rising(close, 2)
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))
  bearKill = roc(close, 13) < 0 && bars_in_trade >= 5

  function onBar() {
    when position() == 0: path.clear()

    when stickyOn && bar_index == 1: {
      path.set(5)
      long()
    }
    when stickyOn && stickySleeveExit(r5): flat()
    when stickyOn && bearKill: flat()
    // After bear-killed seed, do NOT re-enter on IWM (stay flat cash)

    when atrOn && thrust > vol && rising(close, 2): {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): flat()

    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.04 * equity || bars_in_trade >= 8 || bearKill): flat()

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
      || (stickyOn && unrealized_pnl < -0.05 * equity)
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
