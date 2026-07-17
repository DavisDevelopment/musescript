strategy Ema834MacdExit {
  onBar {
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    m = macd(close, 8, 21, 5)
    when e8 > e34 && high >= highest(high, 21): long()
    when e8 < e34 || low <= lowest(low, 13): flat()
    when m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
