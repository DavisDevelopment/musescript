template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy Squeeze834Fall13 {
  a13 = atr(close, 13)
  a55 = atr(close, 55)
  TrailingStop(0.05)
  onBar {
    when a13 < a55 * 0.85 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(a13, 3, 8): flat()
  }
}
