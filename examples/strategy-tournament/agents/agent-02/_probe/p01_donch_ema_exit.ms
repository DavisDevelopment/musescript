strategy DonchEma21Exit {
  onBar {
    e8 = ema(close, 8)
    e21 = ema(close, 21)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || e8 < e21: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
