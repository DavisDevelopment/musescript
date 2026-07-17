template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}

strategy S02_Ema889SlowTrendR7 {
  fast = ema(close, 8)
  slow = ema(close, 89)
  spread = fast - slow

  TrailingStop(0.05)

  onBar {
    when emaTrendEntry(8, 89) && close > slow: long()
    when crossunder(fast, slow) || close < slow: flat()
  }

  onPosition {
    when bars_in_trade >= 34: flat()
    when bars_in_trade >= 13 && unrealized_pnl > 0.034 * equity: flat()
    when falling(spread, 5, 8): flat()
  }
}
