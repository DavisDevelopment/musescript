strategy S03_Ema521T21 {
  fast = ema(close, 5)
  slow = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
  }
}
