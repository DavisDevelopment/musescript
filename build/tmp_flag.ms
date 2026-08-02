template donchHigh(len: Window) -> Bool { high >= highest(high, len) }
template donchLow(len: Window) -> Bool { low <= lowest(low, len) }
template belowEma(len: Window) -> Bool { close < ema(close, len) }
template macdBear(fast: Window, slow: Window, sig: Window) -> Bool { macd(close, fast, slow, sig).hist < 0 }
template rsiHot(len: Window, hi: Scalar) -> Bool { rsi(close, len) > hi }
template rsiCold(len: Window, lo: Scalar) -> Bool { rsi(close, len) < lo }
template crownExit(fastEma: Window) -> Bool {
  donchLow(13) || rsiHot(13, 75) || rsiHot(8, 78) || rsiCold(13, 35) || rsiCold(8, 32) || macdBear(13, 34, 8) || belowEma(fastEma)
}

module RiskKit(stopPct: Scalar = 0.05, timeBars: Window = 13, lockBars: Window = 8, lockPct: Scalar = 0.03) {
  onPosition {
    when unrealized_pnl < -stopPct * equity: flat()
    when bars_in_trade >= timeBars: flat()
    when bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity: flat()
  }
}

indicator function regimeScore(_look) {
  xs = window(close, 21)
  rets = sci_diff(xs)
  bull = avg(rets)
  calm = -stat_stddev(xs)
  thrust = mom(close, 8)
  probs = ml_softmax([bull, calm, thrust])
  return probs[0]
}

strategy FlagshipV0 {
  param donchIn: Window = 21
  param fastEma: Window = 8
  param midEma: Window = 13
  param slowEma: Window = 34
  param rsiLen: Window = 13
  param bbLen: Window = 21

  r = rsi(close, rsiLen)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, slowEma)
  bb = bbands(close, bbLen, 2.0)
  reg = regimeScore(21)

  use RiskKit(stopPct = 0.05, timeBars = 13, lockBars = 8, lockPct = 0.03)

  onBar() when (crownExit(midEma) || reg < 0.22) {
    flat()
  }
  onBar() when (close > eFast && donchHigh(donchIn)) {
    long()
  }
  onBar() {
    when falling(r, 3, 5): flat()
  }

  onPosition {
    when bars_in_trade >= 5 && close < eMid: flat()
    when bars_in_trade >= 8 && close < eSlow && m.hist < 0: flat()
    when bars_in_trade >= 5 && falling(r, 3): flat()
    when close >= bb.upper && unrealized_pnl > 0: flat()
  }
}
