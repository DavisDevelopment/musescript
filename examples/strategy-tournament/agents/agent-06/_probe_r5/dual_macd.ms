strategy DualMacd {
  slow = macd(close, 13, 34, 8)
  fast = macd(close, 8, 21, 5)
  ema13 = ema(close, 13)
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || slow.hist < 0 || rsi(close, 13) > 72 || close < ema13: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < ema13: flat()
    when bars_in_trade >= 5 && fast.hist < 0 && slow.hist < 0: flat()
    when bars_in_trade >= 8 && close < ema(close, 34) && slow.hist < 0: flat()
  }
}
