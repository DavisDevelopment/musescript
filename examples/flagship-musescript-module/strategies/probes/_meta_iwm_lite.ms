// Patch probe: meta sticky DNA but NO kelly/entropy/cuts/brain on IWM path.
class FlagshipMetaIwmLite extends FlagshipRisk {
  param midEma: Window = 13

  path = new PathLatch()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  mf = macd(close, 8, 21, 5)
  m = macd(close, 13, 34, 8)
  roc21 = roc(close, 21)

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  crownOn = (!stickyOn) && (!symbol_is("AAPL")) && (!symbol_is("MSFT"))
  iwmRoom = (!symbol_is("IWM")) || (nFill.get() < 3.0)

  iwmPulse = symbol_is("IWM") && crownOn && roc21 < -0.04
    && position() == 0 && iwmRoom && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    when path.is(5) && return_since_entry() <= 0.0: stickyGate.clear()
    path.clear()
    flat()
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): bail()
  }

  function onBar() {
    when symbol_is("IWM") && bar_index == 1 && primed.get() < 0.5: {
      stickyGate.set(1)
      path.set(5)
      tickFill()
      long()
      primed.set(1)
    }
    when (!symbol_is("IWM")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)

    when stickyOn && bar_index >= 55 && r5 < 45: {
      stickyGate.clear()
      bail()
    }
    when stickyOn && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {
      stickyGate.clear()
      bail()
    }
    when stickyOn && bars_in_trade >= 3 && unrealized_pnl < -0.02 * equity: {
      stickyGate.clear()
      bail()
    }

    when iwmPulse: {
      path.set(7)
      tickFill()
      long()
    }
    when path.is(7) && (bars_in_trade >= 5 || close < e8): bail()
  }

  function hardStopped() {
    return ((!stickyOn) && unrealized_pnl < -stopPct * equity)
      || (crownOn && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return (path.is(7) && bars_in_trade >= 5)
      || (crownOn && bars_in_trade >= timeBars)
  }

  function profitLocked() {
    return crownOn && bars_in_trade >= 5 && falling(r, 3)
  }
}
