template midEmaCross(fast: Window, slow: Window) -> Bool {
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

strategy S04_Ema1321Hard {
  fast = ema(close, 13)
  slow = ema(close, 34)

  onBar {
    when midEmaCross(13, 34): long()
    when crossunder(fast, slow): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 55: flat()
  }
}
