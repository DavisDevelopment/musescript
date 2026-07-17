strategy FlagshipT21 {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 13 && unrealized_pnl > 0.04 * equity: flat()
  }
}