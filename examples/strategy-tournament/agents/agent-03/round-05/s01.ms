strategy MacdFall3Crown {
  m = macd(close, 8, 21, 5)
  fast = ema(close, 13)

  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when falling(m.hist, 3) || crossunder(m.macd, m.signal): flat()
  }
}
