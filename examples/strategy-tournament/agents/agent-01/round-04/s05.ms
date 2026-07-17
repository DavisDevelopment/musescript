strategy S05_Ema834MomMacdPos {
  onBar {
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    m = macd(close, 8, 21, 5)
    when e8 > e34 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when m.hist < 0 && mom(close, 8) < 0: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
