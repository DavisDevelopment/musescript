strategy Squeeze834Don13 {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  onBar {
    when a8 < a34 * 0.89 && high >= highest(high, 13): long()
    when low <= lowest(low, 8): flat()
  }
  onPosition {
    when bars_in_trade >= 8: flat()
  }
}
