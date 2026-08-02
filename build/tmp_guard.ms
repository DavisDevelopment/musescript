strategy S {
  onBar() when (rsi(close, 14) > 70) { flat() }
  onBar() when (crossover(sma(close, 8), sma(close, 21))) { long() }
  onBar() { }
}
