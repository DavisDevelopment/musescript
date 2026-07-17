template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeCap(n: Window) {
  onPosition {
    when bars_in_trade >= n: flat()
  }
}

strategy SqueezeFallAtr {
  a13 = atr(close, 13)
  a55 = atr(close, 55)
  TrailingStop(0.05)
  TimeCap(13)
  onBar {
    when a13 < a55 * 0.85 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 8 && falling(a13, 3, 5): flat()
  }
}
