// v4b — crown-first latch, ATR exit-upgrade, tighter sticky, no calm seed.

class ProbeV4b extends FlagshipRisk {
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

  crownSig = close > e8 && donchHigh(donchIn)
  atrSig = reg >= bullCut && thrust > vol && rising(close, 2)
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  crownSticky = path.is(1) && unrealized_pnl > 0.03 * equity && roc(close, 13) > 0 && bars_in_trade >= 13

  function onBar() {
    when position() == 0 && path.get() != 0: path.clear()

    // Crown-first (SPY/QQQ/AMD), then ATR, bounce, zero
    when position() == 0 && crownSig: {
      path.set(1)
      long()
    }
    when position() == 0 && atrSig: {
      path.set(2)
      long()
    }
    when position() == 0 && bounceSig: {
      path.set(3)
      long()
    }
    when position() == 0 && zeroSig: {
      path.set(4)
      long()
    }

    // Exit-sleeve upgrade: crown trade that starts thrusting uses ATR exits (AAPL)
    when path.is(1) && atrSig && bars_in_trade >= 1: path.set(2)

    // Seed-like sticky only for deep green crown holds
    when crownSticky && stickySleeveExit(r5): {
      path.clear()
      flat()
    }
    when crownSticky && unrealized_pnl < -0.08 * equity: {
      path.clear()
      flat()
    }

    when path.is(2) && atrSleeveExit(8): {
      path.clear()
      flat()
    }
    when path.is(1) && (!crownSticky) && softCrownExit(midEma): {
      path.clear()
      flat()
    }
    when path.is(3) && bounceSleeveExit(): {
      path.clear()
      flat()
    }
    when path.is(4) && (mz.hist < 0 || bars_in_trade >= 13 || rsiHot(13, 78)): {
      path.clear()
      flat()
    }
  }

  function hardStopped() {
    return (crownSticky && unrealized_pnl < -0.08 * equity)
      || ((!crownSticky) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13 && path.is(1)) || (bars_in_trade >= 5 && close < e8 && path.is(2))))
  }

  function timedOut() {
    return (!crownSticky) && (
      (path.is(2) && bars_in_trade >= 21)
      || ((path.is(3) || path.is(4)) && bars_in_trade >= 13)
      || (path.is(1) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    )
  }

  function profitLocked() {
    return (!crownSticky) && (
      (path.is(2) && bars_in_trade >= 8 && falling(r, 3) && r > 70)
      || ((path.is(3) || path.is(4)) && bars_in_trade >= 5 && unrealized_pnl > 0.02 * equity)
      || (path.is(1) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
    )
  }
}
