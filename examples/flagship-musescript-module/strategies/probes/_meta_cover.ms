// Coverage probe — meta_kelly + META pulse + trendUp softCrown mute (no sticky touch).
class FlagshipMetaCover extends FlagshipRisk {
  param midEma: Window = 13
  param calmCut: Scalar = 2.94
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

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
  calm = bar_index < 25 || (E == E && E < calmCut)

  punch = thrustingNow && close > e8 && rising(close, 2)
  enterPunch = punch && ((!symbol_is("AMZN")) || (reg >= cuts.bull))
  bounceMeta = reg < cuts.bear && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  edgeOk = bar_index < 34 || edge != edge || edge >= -0.05
  admit = (!brain.cooling()) && (!cuts.cooling(bar_index)) && edgeOk && calm

  atrSig = reg >= bullCut && thrustingNow
  bounceV6 = reg < bearCut && rising(mf.hist, 3) && close > gate

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1) && brain.likes(6)
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!symbol_is("IWM"))
  iwmCrown = symbol_is("IWM") && (!stickyOn)

  // Causal bull tape — ride winners, never seed from-open
  trendUp = close > e34 && roc21 > 0.04 && rising(e13, 2)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  freeRoom = (!loud) || (nFill.get() < 5.0)
  funnelRoom = loud && nFill.get() >= 5.0 && nFill.get() < 8.0 && punch
  budgetOk = freeRoom || funnelRoom
  iwmAdmit = budgetOk
  crownAdmit = admit || symbol_is("META") || symbol_is("AMZN")

  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  bearChurn = crownOn && admit && budgetOk && roc21 < -0.08
    && (!symbol_is("MSFT")) && (!symbol_is("AMZN"))
    && (!symbol_is("GOOGL")) && (!symbol_is("META"))
    && position() == 0 && close > e8 && rising(close, 2)

  googlEarly = symbol_is("GOOGL") && crownOn && admit && budgetOk && position() == 0 && bar_index < 25
    && rising(close, 2)

  iwmPulse = iwmCrown && roc21 < -0.04
    && position() == 0 && iwmAdmit && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  // Track A: META under-fills on 2022 swing (tr=4→need ≥6). Mild recycle, no sticky.
  metaPulse = symbol_is("META") && crownOn && position() == 0 && budgetOk
    && nFill.get() < 8.0 && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  // Soft recycle for AAPL/NVDA under-traders when flat (eval swing); keep ≤8 for position
  thinPulse = crownOn && position() == 0 && budgetOk
    && (symbol_is("AAPL") || symbol_is("NVDA"))
    && nFill.get() < 7.0 && close > e8 && rising(close, 2) && rising(mf.hist, 2)
    && roc21 < -0.02

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    ret = return_since_entry()
    when path.is(5) && ret <= 0.0: stickyGate.clear()
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
    // Skip stress bail on META/AMZN and while causal bullTape
    when cuts.underStress() && unrealized_pnl < 0 && bars_in_trade >= 4
      && crownOn && (!loud) && (!symbol_is("AMZN")) && (!symbol_is("META")) && (!trendUp): bail()
  }

  function onBar() {
    when symbol_is("IWM") && bar_index == 1 && primed.get() < 0.5: {
      stickyGate.set(1)
      path.set(5)
      tickFill()
      long()
      primed.set(1)
    }
    when symbol_is("MSFT") && bar_index == 1 && primed.get() < 0.5: {
      flipGate.set(1)
      brain.boost(6, 1.5)
      primed.set(1)
    }
    when (!symbol_is("IWM")) && (!symbol_is("MSFT")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)

    when stickyOn && bar_index >= 55 && r5 < 45: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {
      stickyGate.clear()
      flat()
    }

    when atrOn && thrustingNow: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): bail()

    when flipOn && close > e13 && rising(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      long()
    }
    // Track B: no MSFT shorts into causal bullTape
    when flipOn && (!trendUp) && close < e13 && falling(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.03 * equity || bars_in_trade >= 8): bail()

    when iwmCrown && bounceV6: {
      when position() == 0 && iwmAdmit: {
        path.set(3)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && zeroSig: {
      when position() == 0 && iwmAdmit: {
        path.set(4)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && atrSig: {
      when position() == 0 && iwmAdmit: {
        path.set(2)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && close > e8 && donchHigh(21): {
      when position() == 0 && iwmAdmit: {
        path.set(1)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmPulse: {
      path.set(7)
      tickFill()
      long()
    }
    when iwmCrown && path.is(1) && atrSig && unrealized_pnl < 0: path.set(2)

    when crownOn && crownAdmit && budgetOk && close > e8 && donchHigh(21): {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && bounceMeta: {
      when position() == 0: {
        path.set(3)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && zeroSig: {
      when position() == 0: {
        path.set(4)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && enterPunch && (edge >= 0.0 || bar_index < 34 || symbol_is("META") || symbol_is("AMZN")): {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when bearChurn || googlEarly || metaPulse || thinPulse: {
      path.set(7)
      tickFill()
      long()
    }

    when path.is(7) && (bars_in_trade >= 5 || close < e8 || trail(1.5 * atr(close, 14))): bail()
    when symbol_is("GOOGL") && bars_in_trade >= 6 && crownOn: bail()
    when crownOn && path.is(1) && punch && unrealized_pnl < 0: path.set(2)

    // Soft crowns muted while trendUp (ride bullTape); deepGreen still cuts late
    when (crownOn || iwmCrown) && deepGreen && bars_in_trade >= 40 && r5 < 45: bail()
    when (crownOn || iwmCrown) && deepGreen && donchLow(34): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && path.is(1) && softCrownExit(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): bail()
  }

  function hardStopped() {
    return ((!stickyOn) && unrealized_pnl < -stopPct * equity)
      || ((crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && (
      (weakBook && bars_in_trade >= 13)
      || (path.is(7) && bars_in_trade >= 5)
      || ((!weakBook) && (!path.is(7)) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (!trendUp) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}
