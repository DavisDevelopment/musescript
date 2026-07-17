strategy MacdCrossMom {
  fast = ema(close, 8)
  slow = ema(close, 13)
  onBar {
    m = macd(close, 8, 13, 5)
    when crossover(m.macd, m.signal) && fast > slow: long()
    when crossunder(m.macd, m.signal) && mom(close, 5) < 0: flat()
  }
}
