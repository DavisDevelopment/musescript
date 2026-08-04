strategy SetupMemory {
  // bars_since = setup memory: buy the reclaim only if a MACD-cross setup happened recently.
  m = macd(close, 8, 21, 5)
  onBar {
    when bars_since(crossover(m.macd, m.signal)) <= 5 && close > ema(close, 8): long()
    when crossunder(m.macd, m.signal) || bars_since(close > ema(close, 21)) > 8: flat()
  }
}
