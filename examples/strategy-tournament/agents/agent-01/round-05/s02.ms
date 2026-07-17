strategy S02_Cross813FallR5 {
  fast = ema(close, 8)
  slow = ema(close, 13)
  m = macd(close, 8, 21, 5)

  onBar {
    when crossover(fast, slow) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when falling(m.hist, 2) || crossunder(m.macd, m.signal): flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when rsi(close, 13) > 72: flat()
  }
}
