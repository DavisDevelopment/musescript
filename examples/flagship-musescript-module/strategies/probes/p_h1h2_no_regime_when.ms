// H1+H2 — strip regime gate, restore parallel when (keep class risk + templates).

class ProbeNoRegimeWhen extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, 34)
  reg = regimeScore(21) // diagnostic only — not an entry gate

  function onBar() {
    when close > eFast && donchHigh(donchIn): long()
    when crownExit(midEma): flat()
    when falling(r, 3, 5): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < eMid)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < eSlow && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || falling(r, 3)
  }
}
