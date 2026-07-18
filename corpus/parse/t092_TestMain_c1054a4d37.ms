
module Guard(pct: Scalar = 0.05) {
  onBar { when close < 0: flat(); }
}
strategy S {
  use Guard(pct = 0.05)
  onBar { when crossover(sma(close, 8), sma(close, 21)): long(); }
}