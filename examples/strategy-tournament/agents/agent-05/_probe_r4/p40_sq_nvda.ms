strategy Sq513Don13Hard {
  onBar {
    sq = atr(close, 5) < atr(close, 13) * 0.98
    when sq && high >= highest(high, 13): long()
    when low <= lowest(low, 5): flat()
  }
  onPosition {
    when bars_in_trade >= 8: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
