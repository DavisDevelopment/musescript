strategy ProbePureCross {
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}
