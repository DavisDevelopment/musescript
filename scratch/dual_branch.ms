template donHigh(n: Window) -> Bool { high >= highest(high, n) }
strategy PerInstrument {
  fast = ema(close, 8)
  slow = ema(close, 34)
  m = macd(close, 8, 21, 5)
  onBar {
    when asset_is("crypto") && donHigh(13) && m.hist > 0: long()
    when asset_is("forex") && fast > slow: long()
    when close < slow: flat()
  }
}
