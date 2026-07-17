strategy Ema834Ema89Gate {
  onBar {
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    e89 = ema(close, 89)
    when e8 > e34 && close > e89 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
