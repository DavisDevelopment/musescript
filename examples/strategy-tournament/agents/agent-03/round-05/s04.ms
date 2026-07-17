strategy MacdFall3ProfitAnchor {
  m = macd(close, 8, 21, 5)

  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 8 && (falling(m.hist, 3) || crossunder(m.macd, m.signal)): flat()
    when bars_in_trade >= 5 && falling(m.hist, 2): flat()
  }
}
