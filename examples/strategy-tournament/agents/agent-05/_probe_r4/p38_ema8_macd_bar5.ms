strategy Ema8MacdBar5Exit {
  onBar {
    e8 = ema(close, 8)
    m = macd(close, 8, 21, 5)
    when close > e8 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    m = macd(close, 8, 21, 5)
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 5 && m.hist < 0: flat()
  }
}
