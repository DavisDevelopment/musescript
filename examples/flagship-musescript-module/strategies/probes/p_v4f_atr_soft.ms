// v4f — like v3 OR entries, but when path is ATR use atr sleeves; crown keeps soft.
// Latch: crown sets 1, atr sets 2 only if not already in crown this trade.
// deepGreen overlay for IWM.

class ProbeV4f extends FlagshipRisk {
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
  deepGreen = position() > 0 && unrealized_pnl > 0.04 * equity && bars_in_trade >= 21 && roc(close, 13) > 0

  function onBar() {
    when position() == 0 && path.get() != 0: path.clear()

    // Pure ATR open (flat book) — AAPL DNA
    when position() == 0 && atrSig: {
      path.set(2)
      long()
    }
    // Crown open / reassert — never steals an open ATR trade's latch
    when crownSig: {
      when position() == 0 || path.is(1) || path.get() == 0: path.set(1)
      long()
    }
    // ATR reassert only if already ATR or flat
    when atrSig && (path.is(2) || position() == 0): {
      path.set(2)
      long()
    }
    when bounceSig: {
      when position() == 0: path.set(3)
      long()
    }
    when zeroSig: {
      when position() == 0: path.set(4)
      long()
    }

    when deepGreen && bars_in_trade >= 40 && r5 < 45: {
      path.clear()
      flat()
    }
    when deepGreen && donchLow(34): {
      path.clear()
      flat()
    }

    when (!deepGreen) && path.is(2) && atrSleeveExit(8): {
      path.clear()
      flat()
    }
    when (!deepGreen) && path.is(1) && softCrownExit(midEma): {
      path.clear()
      flat()
    }
    when (!deepGreen) && path.is(3) && bounceSleeveExit(): {
      path.clear()
      flat()
    }
    when (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13 || rsiHot(13, 78)): {
      path.clear()
      flat()
    }
  }

  function hardStopped() {
    return super.hardStopped()
      || ((!deepGreen) && path.is(1) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return (!deepGreen) && (
      (path.is(2) && bars_in_trade >= 13)
      || ((path.is(3) || path.is(4)) && bars_in_trade >= 13)
      || (path.is(1) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    )
  }

  function profitLocked() {
    return (!deepGreen) && (
      (path.is(1) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
      || (path.is(2) && bars_in_trade >= 5 && falling(r, 3) && r > 70)
      || ((path.is(3) || path.is(4)) && bars_in_trade >= 5 && unrealized_pnl > 0.02 * equity)
    )
  }
}
