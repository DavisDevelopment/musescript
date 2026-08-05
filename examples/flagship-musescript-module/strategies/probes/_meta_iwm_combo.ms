// kelly + brain + cuts together
class FlagshipMetaIwmCombo extends FlagshipRisk {
  param midEma: Window = 13

  path = new PathLatch()
  brain = new SleeveBrain()
  cuts = new OnlineCuts()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  m = macd(close, 13, 34, 8)
  reg = regimeScore(21)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  thrustingNow = thrust > vol && rising(close, 2)
  roc21 = roc(close, 21)
  edge = kelly_criterion(roc(close, 1), 21)
  E = shannon_entropy(close, 21, 8)
  calm = bar_index < 25 || (E == E && E < 2.94)

  punch = thrustingNow && close > e8 && rising(close, 2)
  edgeOk = bar_index < 34 || edge != edge || edge >= -0.05
  admit = (!brain.cooling()) && (!cuts.cooling(bar_index)) && edgeOk && calm

  stickyOn = symbol_is("IWM") && stickyGate.is(1) && brain.likes(5)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1) && brain.likes(6)
  sitting = symbol_is("IWM") && (!brain.likes(5)) && bar_index < 45
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!sitting)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  freeRoom = (!loud) || (nFill.get() < 5.0)
  funnelRoom = loud && nFill.get() >= 5.0 && nFill.get() < 8.0 && punch
  iwmRoom = (!symbol_is("IWM")) || (nFill.get() < 3.0)
  budgetOk = (freeRoom || funnelRoom) && iwmRoom
  crownAdmit = admit || symbol_is("META") || symbol_is("AMZN")

  bounceSig = reg < cuts.bear && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  enterPunch = punch && ((!symbol_is("AMZN")) || (reg >= cuts.bull))
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  iwmPulse = symbol_is("IWM") && crownOn && roc21 < -0.04
    && position() == 0 && budgetOk && close > e8 && rising(close, 2) && rising(mf.hist, 2)
  iwmRecover = symbol_is("IWM") && (!stickyOn) && (!sitting) && position() == 0
    && budgetOk && close > e8 && rising(close, 3) && donchHigh(21)

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
    when path.is(6): {
      brain.learn(6, ret)
      when ret <= -0.015: flipGate.clear()
    }
    when path.is(2) || path.is(3): brain.learn(path.get(), ret)
    when path.is(1) || path.is(3) || path.is(4) || path.is(7): cuts.learn(ret, bar_index)
    path.clear()
    flat()
  }

  function onPosition() {
    cuts.touchEquity(equity)
    when hardStopped() || timedOut() || profitLocked(): bail()
    when cuts.underStress() && unrealized_pnl < 0 && bars_in_trade >= 4 && crownOn && (!loud) && (!symbol_is("AMZN")): bail()
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

    when crownOn && crownAdmit && budgetOk && close > e8 && donchHigh(21): {
      when position() == 0: { path.set(1); tickFill() }
      long()
    }
    when crownOn && crownAdmit && budgetOk && bounceSig: {
      when position() == 0: { path.set(3); tickFill() }
      long()
    }
    when crownOn && crownAdmit && budgetOk && zeroSig: {
      when position() == 0: { path.set(4); tickFill() }
      long()
    }
    when crownOn && crownAdmit && budgetOk && enterPunch && (edge >= 0.0 || bar_index < 34 || symbol_is("META") || symbol_is("AMZN")): {
      when position() == 0: { path.set(2); tickFill() }
      long()
    }
    when iwmPulse || iwmRecover: {
      path.set(7)
      tickFill()
      long()
    }
    when path.is(7) && (bars_in_trade >= 5 || close < e8 || trail(1.5 * atr(close, 14))): bail()
  }

  function hardStopped() {
    return ((!stickyOn) && unrealized_pnl < -stopPct * equity)
      || (crownOn && (!deepGreen) && bars_in_trade >= 5 && close < e13)
  }
  function timedOut() {
    return (crownOn && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || (path.is(7) && bars_in_trade >= 5)
      || ((!weakBook) && (!path.is(7)) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
  }
  function profitLocked() {
    return (crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
  }
}
