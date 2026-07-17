strategy Ema813Ema21Trail {
  fast = ema(close, 8)
  slow = ema(close, 13)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend: long()
    when position() != 0 && (crossunder(fast, slow) || close < trend): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 34: flat()
  }
}
