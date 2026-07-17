strategy RsiTrendDonchian {
  onBar {
    r = rsi(close, 13)
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    when e8 > e34 && r > 45 && r < 60 && high >= highest(high, 21): long()
    when e8 < e34 || r < 40 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
