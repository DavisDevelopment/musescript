strategy SqueezeDon21Ema {
  a13 = atr(close, 13)
  a55 = atr(close, 55)
  e21 = ema(close, 21)
  onBar {
    when a13 < a55 * 0.85 && close > e21 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
