strategy SqueezeDon13 {
  a13 = atr(close, 13)
  a55 = atr(close, 55)
  onBar {
    when a13 < a55 * 0.85 && high >= highest(high, 13): long()
    when low <= lowest(low, 8): flat()
  }
  onPosition {
    when bars_in_trade >= 8: flat()
  }
}
