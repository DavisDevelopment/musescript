strategy ProbeRsiRisingExit {
  r = rsi(close, 13)
  onBar {
    when position() == 0 && r < 40: long()
    when r > 52: flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 5 && rising(r, 2, 3) && r > 48: flat()
    when bars_in_trade >= 13: flat()
  }
}
