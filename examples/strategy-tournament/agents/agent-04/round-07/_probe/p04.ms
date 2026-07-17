strategy ProbeRsiSlopeExit {
  r13 = rsi(close, 13)
  r8 = rsi(close, 8)
  onBar {
    when position() == 0 && r13 < 32 && close > ema(close, 21): long()
    when r13 > 58 || r8 > 62: flat()
  }
  onPosition {
    when unrealized_pnl < -0.035 * equity: flat()
    when bars_in_trade >= 5 && falling(r13, 3, 3) && r13 < 50: flat()
    when bars_in_trade >= 13: flat()
  }
}
