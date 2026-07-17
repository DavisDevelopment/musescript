strategy Ema813ProfitLock {
  onBar {
    e8 = ema(close, 8)
    e13 = ema(close, 13)
    when e8 > e13 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.03 * equity: flat()
  }
}
