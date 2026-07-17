strategy VectorZscoreGate {
  param look: Window = 21
  xs = window(close, look)
  zs = stat_zscore(xs)
  onBar {
    when zs[look - 1] > 1.0 && rising(close, 2): long()
    when zs[look - 1] < 0: flat()
  }
  onPosition {
    when zs[look - 1] < -0.5: flat()
  }
}
