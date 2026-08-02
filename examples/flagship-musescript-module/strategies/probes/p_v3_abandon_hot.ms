// Keep calm seeds (IWM); abandon hot/weak seeds into v2 active sleeve.

class ProbeV3AbandonHot extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

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
  seedish = position() > 0 && bars_in_trade >= bar_index - 2
  hot = atr(close, 5) / close > 0.012

  function onBar() {
    when bar_index == 1: long()

    // Hot + not clearly winning → hand to active
    when seedish && bar_index >= 12 && hot && unrealized_pnl < 0.03 * equity: flat()
    // Always abandon losing seeds
    when seedish && bar_index >= 12 && unrealized_pnl < 0: flat()

    when (!seedish) && close > e8 && donchHigh(donchIn): long()
    when (!seedish) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!seedish) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!seedish) && crossover(mz.hist, 0) && close > gate: long()

    when seedish && bar_index >= 55 && r5 < 45: flat()
    when seedish && unrealized_pnl < -0.08 * equity: flat()
    when (!seedish) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (!seedish) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13))
  }

  function timedOut() {
    return (!seedish) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0))
  }

  function profitLocked() {
    return (!seedish) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3)))
  }
}
