strategy ProbeLooseRsi {
  r = rsi(close, 13)
  onBar {
    when position() == 0 && r < 45: long()
    when r > 55: flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
