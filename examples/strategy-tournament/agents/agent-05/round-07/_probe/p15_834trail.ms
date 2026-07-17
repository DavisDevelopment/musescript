template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy Squeeze834Trail {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  TrailingStop(0.05)
  onBar {
    when a8 < a34 * 0.89 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
  }
}
