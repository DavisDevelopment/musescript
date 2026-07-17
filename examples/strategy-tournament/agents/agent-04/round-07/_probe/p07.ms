strategy ProbeRsi5Fast {
  r = rsi(close, 5)
  onBar {
    when position() == 0 && r < 25: long()
    when r > 70: flat()
  }
  onPosition {
    when unrealized_pnl < -0.025 * equity: flat()
    when bars_in_trade >= 5: flat()
  }
}
