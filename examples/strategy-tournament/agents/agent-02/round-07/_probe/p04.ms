template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeEma889Level {
  fast = ema(close, 8)
  slow = ema(close, 89)
  spread = fast - slow

  TrailingStop(0.05)

  onBar {
    when (fast > slow || close > fast) && close > slow: long()
    when crossunder(fast, slow) || close < slow: flat()
  }

  onPosition {
    when bars_in_trade >= 34: flat()
    when bars_in_trade >= 13 && unrealized_pnl > 0.034 * equity: flat()
    when falling(spread, 5, 8): flat()
  }
}
