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

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template cascadeExit(fastEma: Window) -> Bool {
  donchianLow(13) || macdBear(13, 34, 8) || rsiOverbought(13, 75) || belowEma(fastEma)
}

template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeExit(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}

strategy ProbeDon13Ema13 {
  e13 = ema(close, 13)
  onBar {
    when close > e13 && donchianHigh(13): long()
    when cascadeExit(13): flat()
  }
  EquityHardStop(0.08)
  TimeExit(21)
}
