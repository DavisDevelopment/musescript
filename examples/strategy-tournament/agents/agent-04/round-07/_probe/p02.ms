strategy ProbeRsiRecovery {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  onBar {
    when position() == 0 && r8 > 30 && r8[1] <= 30 && r13 > 35: long()
    when r13 > 60 || r8 > 65: flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
