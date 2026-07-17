strategy MacdMomLatch {
  onBar {
    m = macd(close, 8, 21, 5)
    when m.hist > 0: long()
    when m.hist < 0 && mom(close, 8) < 0: flat()
  }
}
