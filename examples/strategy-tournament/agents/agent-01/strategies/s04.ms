strategy S04_Ema813Guard {
  fast = ema(close, 8)
  slow = ema(close, 13)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 34: flat()
  }
}
