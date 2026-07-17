template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy Squeeze834Fall {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  TrailingStop(0.05)
  onBar {
    when a8 < a34 * 0.89 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(a8, 3, 8): flat()
  }
}
