strategy Ema834Plain13 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when position() == 0 && crossover(fast, slow): long()
    when position() != 0 && crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
