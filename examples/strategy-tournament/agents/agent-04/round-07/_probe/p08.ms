strategy ProbeRsiDonLow {
  r = rsi(close, 13)
  onBar {
    when position() == 0 && low <= lowest(low, 13) && r < 42: long()
    when r > 58 || high >= highest(high, 8): flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
