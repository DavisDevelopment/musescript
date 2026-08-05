// v7-D — Meta Kelly + v6l-faithful IWM island.
// IWM is a pure v6l sticky/crown specialist (no brain.likes/kill, no OnlineCuts,
// no entropy/Kelly admit, no stress bail). Non-IWM keeps SleeveBrain+Cuts+Kelly.
// Soft crowns never run while stickyOn. Sticky handoffs = flat() only (v6l).

class FlagshipV7MetaKelly extends FlagshipRisk {
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

  // v6l IWM signals (fixed cuts — not OnlineCuts)
  atrSig = reg >= bullCut && thrustingNow
  bounceV6 = reg < bearCut && rising(mf.hist, 3) && close > gate

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1) && brain.likes(6)
  // Meta crown never touches IWM; iwmCrown is pure v6l post-handoff
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!symbol_is("IWM"))
  iwmCrown = symbol_is("IWM") && (!stickyOn)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  freeRoom = (!loud) || (nFill.get() < 5.0)
  funnelRoom = loud && nFill.get() >= 5.0 && nFill.get() < 8.0 && punch
  budgetOk = freeRoom || funnelRoom
  // IWM admitFlat = budget only (v6l)
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

  // v6l post-handoff pulse
  iwmPulse = iwmCrown && roc21 < -0.04
    && position() == 0 && iwmAdmit && close > e8 && rising(close, 2) && rising(mf.hist, 2)
  metaPulse = symbol_is("META") && crownOn && position() == 0 && budgetOk
    && nFill.get() < 7.0 && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    ret = return_since_entry()
    // v6l path5 demotion — no brain.kill (kill starved bull IWM)
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
    when cuts.underStress() && unrealized_pnl < 0 && bars_in_trade >= 4 && crownOn && (!loud) && (!symbol_is("AMZN")): bail()
  }

  function onBar() {
    // Atomic bar-1 IWM seed (v6l)
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

    // Sticky exits (v6l): clear gate + flat — no bail, no path.is(5) guard
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
    when flipOn && close < e13 && falling(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.03 * equity || bars_in_trade >= 8): bail()

    // ——— IWM crown island (exact v6l structure) ———
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

    // ——— Meta crown (non-IWM) ———
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
    when bearChurn || googlEarly || metaPulse: {
      path.set(7)
      tickFill()
      long()
    }

    when path.is(7) && (bars_in_trade >= 5 || close < e8 || trail(1.5 * atr(close, 14))): bail()
    when symbol_is("GOOGL") && bars_in_trade >= 6 && crownOn: bail()
    when crownOn && path.is(1) && punch && unrealized_pnl < 0: path.set(2)

    // Soft crowns: meta under crownOn; IWM under iwmCrown (never stickyOn)
    when (crownOn || iwmCrown) && deepGreen && bars_in_trade >= 40 && r5 < 45: bail()
    when (crownOn || iwmCrown) && deepGreen && donchLow(34): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && path.is(1) && softCrownExit(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): bail()
  }

  function hardStopped() {
    return ((!stickyOn) && unrealized_pnl < -stopPct * equity)
      || ((crownOn || iwmCrown) && (!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || (path.is(7) && bars_in_trade >= 5)
      || ((!weakBook) && (!path.is(7)) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}
