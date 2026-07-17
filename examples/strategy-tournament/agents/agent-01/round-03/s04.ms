strategy S04_Sma813Donchian {
  onBar {
    s8 = sma(close, 8)
    s13 = sma(close, 13)
    when s8 > s13 && high >= highest(high, 21): long()
    when s8 < s13 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
