strategy ProbeDualExit {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  onBar {
    when position() == 0 && r13 < 38: long()
    when r13 > 55 || r8 > 58: flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 5 && falling(r13, 2, 3): flat()
    when bars_in_trade >= 8: flat()
  }
}
