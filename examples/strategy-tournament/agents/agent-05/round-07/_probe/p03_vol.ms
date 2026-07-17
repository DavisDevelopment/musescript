strategy VolDon21 {
  vAvg = sma(volume, 21)
  onBar {
    when (volume <= 0 || volume > vAvg) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
