// Thrust 2 — online cut mutation + drawdown self-tighten (intra-run).
// bull/bear/calm/deep drift from closed-trade outcomes; DD>3% clamps entries.
// Cool-off after a loss. Symbol lifts still present but gated by live cuts.

class FlagshipV6b extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13

  path = new PathLatch()
  cuts = new OnlineCuts()

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
  volPct = atr(close, 14) / close
  roc55 = roc(close, 55)
  thrustingNow = thrust > vol && rising(close, 2)

  atrSig = reg >= cuts.bull && thrustingNow
  bounceSig = reg < cuts.bear && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  stickyOn = symbol_is("IWM") && volPct < cuts.calm && (!cuts.underStress())
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && roc55 < cuts.deep && (!cuts.underStress())
  cool = cuts.cooling(bar_index)
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!cool)

  function bail() {
    cuts.learn(return_since_entry(), bar_index)
    path.clear()
    flat()
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): bail()
  }

  function onBar() {
    cuts.touchEquity(equity)
    when position() == 0: path.clear()

    when stickyOn && bar_index == 1: {
      path.set(5)
      long()
    }
    when stickyOn && position() == 0 && close > e8 && rising(close, 2): {
      path.set(5)
      long()
    }
    when stickyOn && stickySleeveExit(r5): bail()
    when stickyOn && bar_index >= 55 && r5 < 45: bail()

    when atrOn && thrustingNow: {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): bail()

    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.04 * equity || bars_in_trade >= 8): bail()

    when crownOn && bounceSig: {
      when position() == 0: path.set(3)
      long()
    }
    when crownOn && zeroSig: {
      when position() == 0: path.set(4)
      long()
    }
    when crownOn && atrSig: {
      when position() == 0: path.set(2)
      long()
    }
    when crownOn && close > e8 && donchHigh(donchIn): {
      when position() == 0: path.set(1)
      long()
    }
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
    return unrealized_pnl < -stopPct * equity
      || (crownOn && (!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return (crownOn && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || ((!weakBook) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    )
  }
}
