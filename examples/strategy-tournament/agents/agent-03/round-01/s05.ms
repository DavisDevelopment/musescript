strategy MacdRisingGuard {
  trend = ema(close, 13)
  onBar {
    m = macd(close, 8, 21, 5)
    when m.hist > 0 && (rising(close, 2) || close > trend): long()
    when m.hist < 0 && falling(close, 2): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
