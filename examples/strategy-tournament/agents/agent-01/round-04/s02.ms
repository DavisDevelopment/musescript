strategy S02_Ema834CrossDonchian {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
