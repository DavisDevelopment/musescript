strategy Sq513OnlyNvdaPath {
  onBar {
    sq = atr(close, 5) < atr(close, 13) * 0.98
    exp = atr(close, 5) > atr(close, 13)
    when (exp && high >= highest(high, 21)) || (sq && high >= highest(high, 13)): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    m = macd(close, 8, 21, 5)
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when m.hist < 0: flat()
  }
}
