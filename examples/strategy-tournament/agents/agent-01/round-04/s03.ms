strategy S03_Ema834CrossMacdPos {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    m = macd(close, 8, 21, 5)
    when crossover(fast, slow) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when m.hist < 0: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
