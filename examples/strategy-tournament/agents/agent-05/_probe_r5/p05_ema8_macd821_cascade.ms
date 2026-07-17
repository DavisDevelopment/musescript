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

template cascadeExit() -> Bool {
  donchianLow(13) || macdBear(8, 21, 5) || rsiOverbought(13, 72) || belowEma(8)
}

strategy P05_Ema8Macd821Cascade {
  m = macd(close, 8, 21, 5)
  fast = ema(close, 8)
  anchor = ema(close, 21)
  e8 = ema(close, 8)

  onBar {
    when close > e8 && donchianHigh(21): long()
    when cascadeExit(): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()
    when falling(m.hist, 3): flat()
  }
}
