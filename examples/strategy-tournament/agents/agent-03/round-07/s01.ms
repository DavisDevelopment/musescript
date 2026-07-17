strategy MacdHistRegime {
  m = macd(close, 8, 21, 5)
  onBar {
    when m.hist > 0: long()
    when m.hist < 0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
