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

strategy S03_FastSlowExit {
  fast = ema(close, 8)
  slow = ema(close, 21)
  exitMa = ema(close, 34)

  onBar {
    when fastEmaCross(8, 21): long()
    when slowEmaExit(8, 34): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 55: flat()
  }
}
