strategy AboveEma8Sq821 {
  onBar {
    e8 = ema(close, 8)
    when close > e8 && atr(close, 8) < atr(close, 21) * 0.98 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
