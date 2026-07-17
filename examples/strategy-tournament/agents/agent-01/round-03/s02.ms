strategy S02_Ema813Break13 {
  onBar {
    e8 = ema(close, 8)
    e13 = ema(close, 13)
    when e8 > e13 && high >= highest(high, 21): long()
    when e8 < e13 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
