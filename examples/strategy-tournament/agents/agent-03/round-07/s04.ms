template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}
template TimeStop(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}
strategy MacdDonchianFusion {
  m = macd(close, 8, 21, 5)
  TrailingStop(0.08)
  TimeStop(21)
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat()
  }
}
