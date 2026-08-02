// v2c — ATR primary; crown only when also above SMA34 (quality breakouts).

class ProbeV2c extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)

  function onBar() {
    when thrust > vol && rising(close, 2): long()
    when close > e8 && close > gate && donchHigh(donchIn): long()
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    when softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))
  }
}
