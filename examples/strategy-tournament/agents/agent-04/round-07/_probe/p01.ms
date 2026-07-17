strategy ProbeRsiDip {
  r = rsi(close, 13)
  trend = ema(close, 34)
  onBar {
    when position() == 0 && r < 35 && close > trend: long()
    when r > 65: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
