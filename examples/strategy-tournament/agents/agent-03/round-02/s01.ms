strategy MacdTrendTime13 {
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    m = macd(close, 8, 21, 5)
    when m.hist > 0 || fast > slow: long()
    when m.hist < 0 && fast < slow: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
