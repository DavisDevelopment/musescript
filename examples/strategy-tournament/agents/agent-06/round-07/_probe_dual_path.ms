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

template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeExit(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}

strategy ProbeDualPath {
  e8 = ema(close, 8)
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    when (close > e8 && donchianHigh(8)) || crossover(fast, slow): long()
    when cascadeExit(13): flat()
  }
  TrailingStop(0.08)
  TimeExit(21)
}
