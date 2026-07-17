strategy S02_Ema813Ex21 {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, exitMa): flat()
  }
}
