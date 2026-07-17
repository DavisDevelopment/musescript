strategy Ema834Break13Gate {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend && high >= highest(high, 13): long()
    when position() != 0 && (crossunder(fast, slow) || close < trend || low <= lowest(low, 13)): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
