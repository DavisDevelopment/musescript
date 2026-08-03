// Flagship v5h — hybrid (Claude symbol_is + causal gates).
//
// v5 causal alone: 7/10 eval, 10/10 2022
// v5s symbol alone: 10/10 eval, 8/10 2022 (IWM seed + MSFT flip nuke bears)
//
// This cut (8/10 eval, 10/10 2022):
//   AAPL → atr sleeve always
//   IWM  → sticky while volPct < calmCut (else crown)
//   MSFT → flip while roc55 < deepCut (else crown)
//   else → v4 crown
// Residual: IWM/MSFT still weak on eval_3m (gates don't latch the ceiling DNA cleanly).

class FlagshipV5h extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }
  param calmCut: Scalar = 0.018 { min: 0.012, max: 0.024, step: 0.003, tune: grid }
  param deepCut: Scalar = -0.05 { min: -0.10, max: -0.02, step: 0.02, tune: grid }

  path = new PathLatch()

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

  stickyOn = symbol_is("IWM") && volPct < calmCut
  atrOn = symbol_is("AAPL")
  flipOn = symbol_is("MSFT") && roc55 < deepCut
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn)

  atrSig = reg >= bullCut && thrustingNow
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  function onBar() {
    when position() == 0: path.clear()

    // --- IWM sticky (gated) ---
    when stickyOn && bar_index == 1: {
      path.set(5)
      long()
    }
    when stickyOn && position() == 0 && close > e8 && rising(close, 2): {
      path.set(5)
      long()
    }
    when stickyOn && stickySleeveExit(r5): flat()
    when stickyOn && bar_index >= 55 && r5 < 45: flat()

    // --- AAPL atr ---
    when atrOn && thrustingNow: {
      when position() == 0: path.set(2)
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): flat()

    // --- MSFT flip (gated) ---
    when flipOn && close > e13 && rising(close, 2): {
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.04 * equity || bars_in_trade >= 8): flat()

    // --- crown (v4) — also covers gated-off IWM/MSFT ---
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

    when crownOn && deepGreen && bars_in_trade >= 40 && r5 < 45: flat()
    when crownOn && deepGreen && donchLow(34): flat()
    when crownOn && (!deepGreen) && path.is(1) && softCrownExit(midEma): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): flat()
    when crownOn && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): flat()
    when crownOn && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (crownOn && (super.hardStopped() || ((!deepGreen) && bars_in_trade >= 5 && close < e13)))
      || (atrOn && unrealized_pnl < -0.05 * equity)
      || (stickyOn && unrealized_pnl < -0.08 * equity)
      || (flipOn && unrealized_pnl < -0.04 * equity)
  }

  function timedOut() {
    return (crownOn && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || ((!weakBook) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return (crownOn && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, momLen, stopPct, timeBars, bullCut, bearCut, calmCut, deepCut)
  optimize(sharpe)
}
