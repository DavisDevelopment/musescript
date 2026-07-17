strategy MacdFall3Cross {
  onBar {
    m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(m.hist, 3) || crossunder(m.macd, m.signal): flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
