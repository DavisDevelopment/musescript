strategy Ema834Ema21Donchian {
  onBar {
    e8 = ema(close, 8)
    e21 = ema(close, 21)
    e34 = ema(close, 34)
    when e8 > e34 && close > e21 && high >= highest(high, 21): long()
    when e8 < e34 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
