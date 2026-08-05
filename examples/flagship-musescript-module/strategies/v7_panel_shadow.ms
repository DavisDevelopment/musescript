// v7-B — Panel shadow + light specialists.
// Shadow soul: percent_rank(mom)×slope (mom_of dead on per-sym tapes).
// Amp: IWM/AAPL/MSFT specialists for dual; keep wide trail for dBH; loud ≤8.

class FlagshipV7PanelShadow extends FlagshipRisk {
  param midEma: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param rankCut: Scalar = 0.40

  path = new PathLatch()
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
  reg = regimeScore(21)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  thrustingNow = thrust > vol && rising(close, 2)

  spyLive = sym_available("SPY")
  qqqLive = sym_available("QQQ")
  peerLive = spyLive || qqqLive
  spyMom = mom_of("SPY", 13)
  qqqMom = mom_of("QQQ", 13)
  peerRisk = (spyMom > 0.0) || (qqqMom > 0.0)

  ownMom = mom(close, 13)
  rankish = percent_rank(ownMom, 34)
  slopeOk = slope(close, 13) > 0.0
  localShadow = bar_index >= 34 && ((rankish > rankCut && slopeOk) || (rankish > 0.58))
  earlySeed = bar_index >= 8 && bar_index < 34 && slopeOk && rising(close, 2) && close > e8
  // Soft risk: allow slope+ema even when rank mid — indexes were starving
  softRisk = bar_index >= 21 && slopeOk && close > e8 && rising(close, 2)
  riskOn = (peerLive && peerRisk) || ((!peerLive) && (localShadow || earlySeed || softRisk))

  punch = thrustingNow && rising(close, 2) && close > e8
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1)
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  budgetOk = (!loud) || (nFill.get() < 8.0)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    when path.is(5) && return_since_entry() <= -0.015: stickyGate.clear()
    when path.is(6) && return_since_entry() <= -0.015: flipGate.clear()
    path.clear()
    flat()
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): bail()
    when crownOn && (!riskOn) && bars_in_trade >= 6: bail()
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

    when crownOn && riskOn && budgetOk && punch: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when crownOn && riskOn && budgetOk && close > e8 && donchHigh(21): {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && riskOn && budgetOk && bounceSig: {
      when position() == 0: {
        path.set(3)
        tickFill()
      }
      long()
    }
    when crownOn && riskOn && budgetOk && zeroSig: {
      when position() == 0: {
        path.set(4)
        tickFill()
      }
      long()
    }

    when path.is(1) && softCrownExit(midEma): bail()
    when path.is(2) && (close < e8 || trail(2.5 * atr(close, 14))): bail()
    when path.is(3) && bounceSleeveExit(): bail()
    when path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when crownOn && position() != 0 && close < e34 && bars_in_trade >= 8: bail()
  }
}
