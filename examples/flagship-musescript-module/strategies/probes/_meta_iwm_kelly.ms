// Lite + kelly/entropy calm gate (does NOT gate IWM seed)
class FlagshipMetaIwmKelly extends FlagshipRisk {
  path = new PathLatch()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  mf = macd(close, 8, 21, 5)
  m = macd(close, 13, 34, 8)
  roc21 = roc(close, 21)
  edge = kelly_criterion(roc(close, 1), 21)
  E = shannon_entropy(close, 21, 8)
  calm = bar_index < 25 || (E == E && E < 2.94)

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  crownOn = (!stickyOn)

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
  }

  function hardStopped() {
    return ((!stickyOn) && unrealized_pnl < -stopPct * equity)
  }
  function timedOut() { return false }
  function profitLocked() { return false }
}
