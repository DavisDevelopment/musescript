strategy MacdHistLatch {
  trend = ema(close, 34)
  onBar {
    m = macd(close, 8, 21, 5)
    when position() == 0 && m.hist > 0 && close > trend: long()
    when position() != 0 && m.hist < 0 && close < trend: flat()
  }
}
