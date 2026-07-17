strategy AboveEma8Exit8 {
  onBar {
    e8 = ema(close, 8)
    when close > e8 && high >= highest(high, 21): long()
    when low <= lowest(low, 8): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
