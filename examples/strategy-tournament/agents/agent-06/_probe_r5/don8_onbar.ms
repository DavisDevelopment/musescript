strategy Don8OnBar {
  m = macd(close, 13, 34, 8)
  fast = ema(close, 13)
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 8) || m.hist < 0 || rsi(close, 13) > 72 || close < fast: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 8 && close < ema(close, 34) && m.hist < 0: flat()
  }
}
