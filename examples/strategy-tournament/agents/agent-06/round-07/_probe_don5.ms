template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

strategy ProbeDon5 {
  onBar {
    when donchianHigh(5): long()
    when close < ema(close, 13): flat()
  }
}
