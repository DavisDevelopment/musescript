strategy Cross813Donch21R4 {
  fast = ema(close, 8)
  slow = ema(close, 13)
  onBar {
    when position() == 0 && crossover(fast, slow) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
