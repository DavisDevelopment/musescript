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
  donchianLow(8) || macdBear(13, 34, 8) || rsiOverbought(13, 72) || belowEma(fastEma)
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

template ProfitLock(minBars: Scalar, pct: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && unrealized_pnl > pct * equity: flat()
  }
}

strategy ProbeDon8Ema8 {
  m8 = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  fast = ema(close, 13)
  onBar {
    when close > e8 && donchianHigh(8): long()
    when cascadeExit(13): flat()
  }
  EquityHardStop(0.08)
  TimeExit(21)
  ProfitLock(8, 0.05)
  onPosition {
    when bars_in_trade >= 5 && close < fast: flat()
    when falling(m8.hist, 3, 5): flat()
  }
}
