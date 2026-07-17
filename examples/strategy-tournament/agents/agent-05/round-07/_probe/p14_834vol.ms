strategy Squeeze834Vol {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  vAvg = sma(volume, 21)
  onBar {
    when a8 < a34 * 0.89 && (volume <= 0 || volume > vAvg) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
