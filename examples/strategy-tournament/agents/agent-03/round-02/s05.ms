strategy MacdDonchianMomExit {
  onBar {
    m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || (m.hist < 0 && mom(close, 8) < 0): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
