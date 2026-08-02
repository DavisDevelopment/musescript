// Hold any long through short-term uptrends; soft-crown only in down/chop.

class ProbeV3UpHold2 extends FlagshipRisk {
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
  upHold = position() > 0 && roc(close, 13) > 0

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when crossover(mz.hist, 0) && close > gate: long()

    when upHold && bars_in_trade >= 40 && r5 < 45: flat()
    when upHold && donchLow(34): flat()
    when upHold && unrealized_pnl < -0.08 * equity: flat()
    when (!upHold) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (!upHold) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13))
  }

  function timedOut() {
    return (!upHold) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0))
  }

  function profitLocked() {
    return (!upHold) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3)))
  }
}
