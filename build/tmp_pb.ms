strategy PullbackEma {
  e8 = ema(close, 8)
  e34 = ema(close, 34)
  onBar {
    when close > e34 && crossover(close, e8): long()
    when crossunder(close, e8) || close < e34: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
