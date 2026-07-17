template fastEmaCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template aboveTrend(len: Window) -> Bool {
  close > sma(close, len)
}

template atrQuiet(fast: Window, slow: Window, ratio: Scalar) -> Bool {
  atr(close, fast) <= atr(close, slow) * ratio
}

template atrQuiet(fast: Window, slow: Window, ratio: Scalar) -> Bool {
  atr(close, fast) <= atr(close, slow) * ratio
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

strategy S02_Ema834Guard {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trend = sma(close, 55)

  onBar {
    when fastEmaCross(8, 34): long()
    when crossunder(fast, slow) || close < trend: flat()
  }

  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 55: flat()
  }
}
