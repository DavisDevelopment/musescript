// Exit-loosened crown — higher RSI TP, drop RSI-cold from onBar (keep onPosition fail).
// Targets MSFT/META/AAPL chop exits.

template softCrownExit(fastEma: Window) -> Bool {
  donchLow(13) || rsiHot(13, 80) || rsiHot(8, 82) || macdBear(13, 34, 8) || belowEma(fastEma)
}

class ProbeExitTune extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)

  function onBar() {
    when close > e8 && donchHigh(donchIn): long()
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
