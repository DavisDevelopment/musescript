template goldenCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template slowEmaExit(fast: Window, exitLen: Window) -> Bool {
  crossunder(ema(close, fast), ema(close, exitLen))
}

template macdBull(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist >= 0
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

strategy S04_GoldenTime {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)

  onBar {
    when goldenCross(8, 13): long()
    when slowEmaExit(8, 21): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.025 * equity: flat()
  }
}
