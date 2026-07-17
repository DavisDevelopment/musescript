template fastEmaCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template slowEmaExit(fast: Window, exitLen: Window) -> Bool {
  crossunder(ema(close, fast), ema(close, exitLen))
}

template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template aboveTrend(len: Window) -> Bool {
  close > sma(close, len)
}

template macdBull(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist > 0
}

template rsiOk(len: Window, lo: Scalar, hi: Scalar) -> Bool {
  rsi(close, len) > lo && rsi(close, len) < hi
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

strategy S05_CascadeR2 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  exitMa = ema(close, 21)
  trend = ema(close, 21)
  anchor = sma(close, 55)
  m = macd(close, 13, 34, 8)

  onBar {
    when position() == 0 && fastEmaCross(8, 34) && close > trend: long()
    when position() == 0 && donchianHigh(21) && aboveTrend(55): long()
    when position() != 0 && (slowEmaExit(8, 21) || donchianLow(13)): flat()
    when position() != 0 && close < anchor: flat()
    when m.hist < 0 && rsi(close, 13) > 72 && position() != 0: flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 13 && unrealized_pnl > 0.04 * equity: flat()
    when bars_in_trade >= 8 && close < trend: flat()
  }
}
