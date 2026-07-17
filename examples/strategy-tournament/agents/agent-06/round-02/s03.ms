template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template fastEmaCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template slowEmaExit(fast: Window, exitLen: Window) -> Bool {
  crossunder(ema(close, fast), ema(close, exitLen))
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

strategy S03_HybridPulse {
  fast = ema(close, 8)
  slow = ema(close, 34)
  exitMa = ema(close, 21)

  onBar {
    when position() == 0 && (fastEmaCross(8, 34) || donchianHigh(21)): long()
    when position() != 0 && (slowEmaExit(8, 21) || donchianLow(13)): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 34: flat()
    when bars_in_trade >= 21 && close < exitMa: flat()
  }
}
