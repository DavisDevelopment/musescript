strategy AtrTrailDon21 {
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 5 && close < entry_price - 2 * atr(close, 8): flat()
  }
}
