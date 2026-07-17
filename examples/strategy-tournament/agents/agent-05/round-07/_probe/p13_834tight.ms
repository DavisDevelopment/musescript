strategy Squeeze834 {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  onBar {
    when a8 < a34 * 0.85 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
