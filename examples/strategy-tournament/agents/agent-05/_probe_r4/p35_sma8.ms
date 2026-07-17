strategy AboveSma8Don21 {
  onBar {
    s8 = sma(close, 8)
    when close > s8 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
