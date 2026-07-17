strategy DualOrDon {
  onBar {
    sq = atr(close, 5) < atr(close, 13) * 0.98
    when (sq && high >= highest(high, 13)) || high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
