strategy TakeDropPulse {
  param look: Window = 34
  xs = window(close, look)
  recent = take(drop(xs, look - 8), 8)
  older = take(xs, 8)
  onBar {
    when avg(recent) > avg(older) && rising(close, 2): long()
    when avg(recent) < avg(older): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
