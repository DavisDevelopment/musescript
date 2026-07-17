template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template rsiMomentumFail(len: Window, lo: Scalar) -> Bool {
  rsi(close, len) < lo
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template rsiMacdCascade(fastEma: Window) -> Bool {
  donchianLow(13) || rsiOverbought(13, 72) || rsiMomentumFail(13, 35) || macdBear(13, 34, 8) || belowEma(fastEma)
}

strategy S05_RsiCrownFlagshipR5 {
  m = macd(close, 13, 34, 8)
  fast = ema(close, 13)
  anchor = ema(close, 34)

  onBar {
    when donchianHigh(21): long()
    when rsiMacdCascade(13): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()
  }
}
