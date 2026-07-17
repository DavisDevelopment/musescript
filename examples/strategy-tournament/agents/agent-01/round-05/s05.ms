strategy S05_Ema834LazyCascadeR5 {
  m = macd(close, 13, 34, 8)
  fast = ema(close, 8)
  slow = ema(close, 34)

  onBar {
    when fast > slow && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when m.hist < 0 && mom(close, 8) < 0: flat()
    when rsi(close, 13) > 72: flat()
    when bars_in_trade >= 5 && close < fast: flat()
  }
}
