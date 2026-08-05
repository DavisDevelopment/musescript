// v7-E — Bracket-structure + specialist seeds.
// Edge = 2ATR stop / 3.2ATR target under next-open; multi-setup enter.
// Amp: IWM/AAPL/MSFT + calm entropy gate + loud/AMD fill budget.

class FlagshipV7BracketStructure extends FlagshipRisk {
  param riskATR: Scalar = 2.0
  param rewardATR: Scalar = 3.2

  path = new PathLatch()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()
  entryATR = new PathLatch()
  entryPx = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  reg = regimeScore(21)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  atr14 = atr(close, 14)
  thrustingNow = thrust > vol && rising(close, 2)
  E = shannon_entropy(close, 21, 8)
  calm = bar_index < 25 || (E == E && E < 2.92)

  breakout = close > e8 && donchHigh(21) && rising(close, 2)
  bounce = reg < 0.22 && rising(mf.hist, 3) && close > gate
  zero = crossover(mz.hist, 0) && close > gate
  punch = thrustingNow && close > e8 && rising(close, 2)
  setup = bar_index >= 21 && calm && (breakout || bounce || zero || punch)

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1)
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn)

  loud = symbol_is("SPY") || symbol_is("QQQ") || symbol_is("AMD")
  budgetOk = (!loud) || (nFill.get() < 6.0)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function markEntry() {
    path.set(1)
    entryATR.set(atr14)
    entryPx.set(close)
    tickFill()
  }

  function bail() {
    when path.is(5) && return_since_entry() <= -0.015: stickyGate.clear()
    when path.is(6) && return_since_entry() <= -0.015: flipGate.clear()
    path.clear()
    entryATR.clear()
    entryPx.clear()
    flat()
  }

  function onPosition() {
    when path.is(5) || path.is(6): {
      when hardStopped() || timedOut() || profitLocked(): bail()
    }
    when path.is(1): {
      risk = entryATR.get()
      when risk < 1e-8: risk = atr14
      ep = entryPx.get()
      when ep < 1e-8: ep = close
      shareProxy = equity / ep
      when unrealized_pnl < -riskATR * risk * shareProxy: bail()
      when unrealized_pnl > rewardATR * risk * shareProxy: bail()
      when trail(1.8 * atr14): bail()
      when bars_in_trade >= 21: bail()
      when close < e8 && bars_in_trade >= 5: bail()
    }
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
      primed.set(1)
    }
    when (!symbol_is("IWM")) && (!symbol_is("MSFT")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)

    when stickyOn && bar_index >= 55 && r5 < 45: {
      stickyGate.clear()
      bail()
    }
    when stickyOn && unrealized_pnl < -0.04 * equity: {
      stickyGate.clear()
      bail()
    }

    when atrOn && thrustingNow: {
      when position() == 0: {
        path.set(2)
        entryATR.set(atr14)
        entryPx.set(close)
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

    when crownOn && setup && budgetOk && position() == 0: {
      markEntry()
      long()
    }
    when crownOn && budgetOk && position() == 0 && nFill.get() < 2.0
      && close > e8 && rising(close, 2) && (symbol_is("AMZN") || symbol_is("GOOGL") || symbol_is("META")): {
      markEntry()
      long()
    }
  }
}
