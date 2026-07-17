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

strategy S03_Ema85DualCascadeR6 {
  m = macd(close, 13, 34, 8)
  m8 = macd(close, 8, 21, 5)
  fast = ema(close, 8)
  micro = ema(close, 5)
  slow = ema(close, 13)
  trail = ema(close, 13)
  anchor = ema(close, 34)

  onBar {
    when (fast > slow || fast > micro) && close > fast && donchianHigh(21): long()
    when cascadeExit(13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < trail: flat()
    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()
    when falling(m8.hist, 3): flat()
  }
}
