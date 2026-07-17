strategy FullStack {
  slow = macd(close, 13, 34, 8)
  fastMacd = macd(close, 8, 21, 5)
  fast = ema(close, 13)
  anchor = ema(close, 34)
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || slow.hist < 0 || rsi(close, 13) > 72 || close < fast: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.02 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 5 && falling(slow.hist, 2) && slow.hist < 0: flat()
    when bars_in_trade >= 5 && close < highest(high, 8) - 2 * atr(close, 8): flat()
    when bars_in_trade >= 8 && close < anchor && fastMacd.hist < 0 && slow.hist < 0: flat()
  }
}
