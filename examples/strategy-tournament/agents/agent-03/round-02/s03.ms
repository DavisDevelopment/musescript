strategy MacdDonchian13x8 {
  onBar {
    m = macd(close, 8, 21, 5)
    when high >= highest(high, 13): long()
    when low <= lowest(low, 8) || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
