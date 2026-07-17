template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A01S02_Sma813BroadR8 {
  fast = sma(close, 8)
  slow = sma(close, 13)
  spread = fast - slow
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when (fast > slow || rising(spread, 2)) && m.hist > -0.001: long()
    when crossunder(fast, slow) || falling(spread, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl > 0.025 * equity: flat()
  }
}
