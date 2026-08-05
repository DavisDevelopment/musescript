// Lite + SleeveBrain + OnlineCuts
class FlagshipMetaIwmBrain extends FlagshipRisk {
  path = new PathLatch()
  brain = new SleeveBrain()
  cuts = new OnlineCuts()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()

  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  mf = macd(close, 8, 21, 5)
  roc21 = roc(close, 21)

  stickyOn = symbol_is("IWM") && stickyGate.is(1) && brain.likes(5)
  sitting = symbol_is("IWM") && (!brain.likes(5)) && bar_index < 45
  crownOn = (!stickyOn) && (!sitting)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    ret = return_since_entry()
    when path.is(5): {
      brain.learn(5, ret)
      when ret <= 0.0: {
        brain.kill(5)
        stickyGate.clear()
      }
    }
    path.clear()
    flat()
  }

  function onPosition() {
    cuts.touchEquity(equity)
    when hardStopped() || timedOut() || profitLocked(): bail()
    when cuts.underStress() && unrealized_pnl < 0 && bars_in_trade >= 4 && crownOn: bail()
  }

  function onBar() {
    when symbol_is("IWM") && bar_index == 1 && primed.get() < 0.5: {
      stickyGate.set(1)
      brain.boost(5, 1.5)
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
    when symbol_is("IWM") && crownOn && roc21 < -0.04 && position() == 0 && nFill.get() < 3.0
      && close > e8 && rising(close, 2) && rising(mf.hist, 2): {
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
  function timedOut() { return path.is(7) && bars_in_trade >= 5 }
  function profitLocked() { return false }
}
