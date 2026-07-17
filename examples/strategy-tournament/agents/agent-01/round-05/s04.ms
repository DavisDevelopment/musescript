strategy S04_Ema813CascadeR5 {
  m = macd(close, 13, 34, 8)
  fast = ema(close, 8)
  anchor = ema(close, 13)

  onBar {
    when fast > anchor && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()
    when falling(m.hist, 2) || crossunder(m.macd, m.signal): flat()
    when rsi(close, 13) > 72: flat()
  }
}
