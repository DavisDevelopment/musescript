strategy MacdCrossMomentum {
  m = macd(close, 8, 21, 5)
  onBar {
    when crossover(m.macd, m.signal): long()
    when crossunder(m.macd, m.signal) || m.hist < 0: flat()
  }
}
