template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy Don21AtrTrail {
  vol = atr(close, 13)
  TrailingStop(0.05)
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && close < entry_price + 1.5 * vol: flat()
    when bars_in_trade >= 5 && falling(vol, 3, 5): flat()
  }
}
