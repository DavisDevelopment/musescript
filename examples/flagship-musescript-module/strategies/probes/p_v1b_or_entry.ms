// OR-broadened entry (crypto/FX DNA) + crown exits — more participation without shorts.

class ProbeOrEntry extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)

  function onBar() {
    when (close > e8 && donchHigh(donchIn)) || ((e8 > e13 || rising(m.hist, 3)) && close > gate): long()
    when crownExit(midEma): flat()
    when falling(r, 3, 5): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || falling(r, 3)
  }
}
