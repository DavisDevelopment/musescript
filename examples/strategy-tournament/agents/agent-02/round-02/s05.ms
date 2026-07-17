strategy Ema821Ema13Gate {
  fast = ema(close, 8)
  slow = ema(close, 21)
  trend = ema(close, 13)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend: long()
    when position() != 0 && (crossunder(fast, slow) || close < trend || low <= lowest(low, 8)): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
