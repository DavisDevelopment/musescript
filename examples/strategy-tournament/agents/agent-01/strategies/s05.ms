strategy S05_Ema834 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}
