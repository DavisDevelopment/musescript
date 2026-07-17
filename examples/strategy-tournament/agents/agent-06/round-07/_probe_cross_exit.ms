template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
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

strategy ProbeCrossExit {
  fast = ema(close, 8)
  slow = ema(close, 21)
  e8 = ema(close, 8)
  onBar {
    when (close > e8 && donchianHigh(8)) || crossover(fast, slow): long()
    when crossunder(fast, slow) || donchianLow(13): flat()
  }
  TrailingStop(0.08)
  TimeExit(21)
}
