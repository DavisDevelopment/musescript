strategy Ema834RsiDipDon {
  onBar {
    r = rsi(close, 13)
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    when e8 > e34 && lowest(r, 13) < 40 && high >= highest(high, 21): long()
    when low <= lowest(low, 13) || e8 < e34: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
