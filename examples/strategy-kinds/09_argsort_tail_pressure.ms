strategy ArgsortTailPressure {
  param look: Window = 21
  xs = window(close, look)
  order = argsort(xs)
  // last argsort index points at the max; if current bar is that max, breakout pressure
  onBar {
    when order[look - 1] >= look - 3 && rising(close, 2): long()
    when order[0] <= 2 && falling(close, 2): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
