strategy AtrChandelierDon21 {
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 3 && close < highest(high, 8) - 3 * atr(close, 8): flat()
  }
}
