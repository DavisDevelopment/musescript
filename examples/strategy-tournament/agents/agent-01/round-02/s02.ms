strategy S02_Ema834Gate {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend: long()
    when position() != 0 && (crossunder(fast, slow) || close < trend): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
