strategy ProbeFxRsiTight {
  r = rsi(close, 21)
  onBar {
    when position() == 0 && r < 38: long()
    when r > 52: flat()
  }
  onPosition {
    when unrealized_pnl < -0.015 * equity: flat()
    when bars_in_trade >= 5 && r > 48: flat()
    when bars_in_trade >= 13: flat()
  }
}
