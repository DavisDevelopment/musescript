template TrailingStop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

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

strategy S03_Ema513RisingCascadeR7 {
  m = macd(close, 13, 34, 8)
  m8 = macd(close, 8, 21, 5)
  fast = ema(close, 5)
  slow = ema(close, 13)
  micro = ema(close, 8)
  spread = fast - slow

  TrailingStop(0.04)

  onBar {
    when (fast > slow || close > micro) && rising(spread, 3): long()
    when cascadeExit(8): flat()
  }

  onPosition {
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && close < micro: flat()
    when bars_in_trade >= 8 && m.hist < 0: flat()
    when falling(m8.hist, 3, 5): flat()
    when crossunder(fast, slow): flat()
  }
}
