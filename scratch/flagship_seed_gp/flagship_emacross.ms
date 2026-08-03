strategy FlagshipEmaCross {
  fast = ema(close, 13)
  slow = ema(close, 45)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}
