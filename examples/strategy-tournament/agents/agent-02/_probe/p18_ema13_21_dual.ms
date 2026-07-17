strategy Ema813Ema21Dual {
  onBar {
    e8 = ema(close, 8)
    e13 = ema(close, 13)
    e21 = ema(close, 21)
    when e8 > e13 && close > e21 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
