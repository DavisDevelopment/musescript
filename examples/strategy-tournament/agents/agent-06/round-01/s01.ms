template goldenCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
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

strategy S01_GoldenVault {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)

  onBar {
    when goldenCross(8, 13): long()
    when crossunder(fast, exitMa): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 34: flat()
  }
}
