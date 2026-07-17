strategy MacdEma8Pos {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && close < ema(close, 8): flat()
  }
}