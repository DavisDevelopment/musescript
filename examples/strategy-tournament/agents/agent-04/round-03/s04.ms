strategy RsiCrossDonchianMacd {
  onBar {
    r = rsi(close, 13)
    m = macd(close, 8, 21, 5)
    when r < 40 && high >= highest(high, 21): long()
    when r > 70 || m.hist < 0 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
