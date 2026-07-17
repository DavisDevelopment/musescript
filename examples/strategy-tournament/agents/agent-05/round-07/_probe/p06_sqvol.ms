strategy SqueezeVolDon21 {
  a13 = atr(close, 13)
  a55 = atr(close, 55)
  vAvg = sma(volume, 21)
  onBar {
    when a13 < a55 * 0.85 && (volume <= 0 || volume > vAvg) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
