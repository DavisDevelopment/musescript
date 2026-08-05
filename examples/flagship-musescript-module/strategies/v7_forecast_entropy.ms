// v7-C — Forecast-entropy gate (UQ admit) + light specialists.
// TODO(ew-decorate): fe/pu → forecast("regime").entropy / .prob_up
// Amp: IWM/AAPL/MSFT; feCut 2.90; chaos 2.97; loud ≤8; keep shannon proxy.

class FlagshipV7ForecastEntropy extends FlagshipRisk {
  param midEma: Window = 13
  param feCut: Scalar = 2.90
  param chaosCut: Scalar = 2.97
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  path = new PathLatch()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()

  fe = shannon_entropy(close, 21, 8)
  pu = roc(close, 8)
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

  ready = bar_index >= 25 && fe == fe
  early = bar_index < 25
  agree = (ready && fe < feCut && (pu > 0.0 || rising(close, 2)))
    || (early && rising(close, 2) && close > e8)
  chaotic = ready && fe >= chaosCut

  punch = thrustingNow && rising(close, 2) && close > e8
  enterPunch = punch && ((!symbol_is("AMZN")) || (reg >= bullCut))
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  trailW = 1.7 + (feCut - fe) * 0.85

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1)
  sitting = symbol_is("IWM") && (!stickyGate.is(1)) && bar_index < 45
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!sitting)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  freeRoom = (!loud) || (nFill.get() < 5.0)
  funnelRoom = loud && nFill.get() >= 5.0 && nFill.get() < 8.0 && punch
  amznRoom = (!symbol_is("AMZN")) || (nFill.get() < 8.0)
  amdRoom = (!symbol_is("AMD")) || (nFill.get() < 3.0)
  budgetOk = (freeRoom || funnelRoom) && amznRoom && amdRoom

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
    when crownOn && chaotic && bars_in_trade >= 2: bail()
    when crownOn && (!agree) && bars_in_trade >= 6: bail()
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
    when stickyOn && bars_in_trade >= 3 && unrealized_pnl < -0.02 * equity: {
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

    when crownOn && agree && budgetOk && enterPunch: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when crownOn && agree && budgetOk && close > e8 && donchHigh(21): {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && agree && budgetOk && bounceSig && (!symbol_is("AMD")): {
      when position() == 0: {
        path.set(3)
        tickFill()
      }
      long()
    }
    when crownOn && agree && budgetOk && zeroSig && (!symbol_is("AMD")): {
      when position() == 0: {
        path.set(4)
        tickFill()
      }
      long()
    }

    when path.is(1) && softCrownExit(midEma): bail()
    when path.is(2) && (close < e8 || trail(trailW * atr(close, 14))): bail()
    when path.is(3) && bounceSleeveExit(): bail()
    when path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when crownOn && position() != 0 && close < e34 && bars_in_trade >= 10: bail()
  }
}
