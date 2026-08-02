// Low realized-vol%: sticky seed/fade (IWM). High vol%: active v2 (SPY/QQQ/NVDA).

class ProbeV3VolSplit extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param calmCut: Scalar = 0.012 { min: 0.008, max: 0.02, step: 0.002, tune: grid }

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
  calm = volPct < calmCut
  seedish = position() > 0 && bars_in_trade >= bar_index - 2

  function onBar() {
    // Calm tape: sticky
    when calm && bar_index == 1: long()
    when calm && position() == 0 && close > e8 && rising(close, 2): long()
    when calm && seedish && bar_index >= 55 && r5 < 45: flat()
    when calm && seedish && unrealized_pnl < -0.08 * equity: flat()

    // Hot tape: v2 active (+ MACD zero)
    when (!calm) && close > e8 && donchHigh(donchIn): long()
    when (!calm) && reg >= bullCut && thrust > vol && rising(close, 2): long()
    when (!calm) && reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when (!calm) && crossover(mz.hist, 0) && close > gate: long()
    when (!calm) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (!calm) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13))
  }

  function timedOut() {
    return (!calm) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0))
  }

  function profitLocked() {
    return (!calm) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3)))
  }
}
