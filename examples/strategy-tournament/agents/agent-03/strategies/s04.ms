strategy MacdRisingRide {
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    m = macd(close, 8, 21, 5)
    when rising(close, 2) || m.hist > 0 || fast > slow: long()
    when falling(close, 2) && m.hist < 0 && fast < slow: flat()
  }
}
