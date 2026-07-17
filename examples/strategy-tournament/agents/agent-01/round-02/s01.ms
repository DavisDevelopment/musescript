strategy S01_Ema834T13 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
