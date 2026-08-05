// v7-A — Hurst × Entropy sleeve router + light v6l specialists.
// H/E soul intact; sticky/atr/flip for dual coverage; loud fill ≤8.
// Cal: E calm≤2.88 / chaos≥2.96; H trend≥0.50 / fade<0.48.
// No early-as-calm (that overtraded 2022); ready gate then sleeves.

class FlagshipV7HurstEntropy extends FlagshipRisk {
  param midEma: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param calmCut: Scalar = 2.88
  param chaosCut: Scalar = 2.96

  path = new PathLatch()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()

  H = hurst_exponent(close, 34)
  E = shannon_entropy(close, 21, 8)
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

  ready = bar_index >= 36 && H == H && E == E
  calm = ready && E < calmCut
  softCalm = ready && E < chaosCut
  confused = ready && E >= chaosCut
  trendMem = ready && H >= 0.50
  fadeMem = ready && H < 0.48

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
    when confused && crownOn && bars_in_trade >= 3: bail()
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

    when crownOn && calm && trendMem && punch && budgetOk: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when crownOn && softCalm && trendMem && close > e8 && donchHigh(21) && budgetOk: {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && softCalm && fadeMem && bounceSig && budgetOk: {
      when position() == 0: {
        path.set(3)
        tickFill()
      }
      long()
    }
    when crownOn && softCalm && fadeMem && zeroSig && budgetOk: {
      when position() == 0: {
        path.set(4)
        tickFill()
      }
      long()
    }
    when crownOn && calm && (!trendMem) && (!fadeMem) && close > e8 && donchHigh(21) && budgetOk: {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && softCalm && (!confused) && punch && budgetOk && nFill.get() < 4.0: {
      when position() == 0 && (!path.is(1)): {
        path.set(2)
        tickFill()
      }
      long()
    }
    // Early seed for tapes that otherwise starve before Hurst warms
    when crownOn && bar_index < 40 && nFill.get() < 2.0 && close > e8 && rising(close, 2) && budgetOk: {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }

    when path.is(1) && softCrownExit(midEma): bail()
    when path.is(2) && (close < e8 || trail(2.0 * atr(close, 14))): bail()
    when path.is(3) && bounceSleeveExit(): bail()
    when path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when crownOn && position() != 0 && bars_in_trade >= 13 && close < e34: bail()
  }
}
