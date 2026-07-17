strategy S04_Ema813Ex21T13 {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, exitMa): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
