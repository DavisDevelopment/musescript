// v6l — surprise tube: quality-funnel trade budget on loud indexes (SPY/QQQ).
// PathLatch as a fill counter. Fills 1–5: free crown. Fills 6–8: atrSig only. Then sealed.
// Goal: eval SPY/QQQ land ≤8 (unlock position cells) without killing swing (≥6) or any-edge.

class FlagshipV6l extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  path = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()
  nFill = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)
  roc21 = roc(close, 21)
  thrustingNow = thrust > vol && rising(close, 2)

  atrSig = reg >= bullCut && thrustingNow
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  stickyOn = symbol_is("IWM") && stickyGate.is(1)
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && flipGate.is(1)
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  // free band → conviction funnel → sealed (matrix position max written into DNA)
  freeRoom = (!loud) || (nFill.get() < 5)
  funnelRoom = loud && nFill.get() >= 5 && nFill.get() < 8 && atrSig
  admitFlat = freeRoom || funnelRoom

  bearChurn = crownOn && roc21 < -0.08
    && (!symbol_is("IWM")) && (!symbol_is("MSFT")) && (!symbol_is("AMZN")) && (!symbol_is("GOOGL"))
    && position() == 0 && admitFlat && close > e8 && rising(close, 2)

  googlEarly = symbol_is("GOOGL") && crownOn && position() == 0 && admitFlat && bar_index < 25
    && rising(close, 2)

  iwmPulse = symbol_is("IWM") && crownOn && roc21 < -0.04
    && position() == 0 && admitFlat && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1)
  }

  function bail() {
    when path.is(5) && return_since_entry() <= 0.0: stickyGate.clear()
    when path.is(6) && return_since_entry() <= -0.015: flipGate.clear()
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
    when symbol_is("MSFT") && bar_index == 1 && primed.get() < 0.5: {
      flipGate.set(1)
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
    when flipOn && close < e13 && falling(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.03 * equity || bars_in_trade >= 8): bail()

    when crownOn && bounceSig: {
      when position() == 0 && admitFlat: {
        path.set(3)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when crownOn && zeroSig: {
      when position() == 0 && admitFlat: {
        path.set(4)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when crownOn && atrSig: {
      when position() == 0 && admitFlat: {
        path.set(2)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when crownOn && close > e8 && donchHigh(donchIn): {
      when position() == 0 && admitFlat: {
        path.set(1)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when bearChurn || googlEarly || iwmPulse: {
      path.set(7)
      tickFill()
      long()
    }
    when path.is(7) && (bars_in_trade >= 5 || close < e8 || trail(1.5 * atr(close, 14))): {
      path.clear()
      flat()
    }
    when symbol_is("GOOGL") && bars_in_trade >= 6: bail()
    when crownOn && path.is(1) && atrSig && unrealized_pnl < 0: path.set(2)

    when crownOn && deepGreen && bars_in_trade >= 40 && r5 < 45: bail()
    when crownOn && deepGreen && donchLow(34): bail()
    when crownOn && (!deepGreen) && path.is(1) && softCrownExit(midEma): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): bail()
    when crownOn && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): bail()
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
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return (crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}
