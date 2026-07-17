strategy BbandsSqueezeRelease {
  param len: Window = 21
  bb = bbands(close, len, 2.0)
  width = bb.upper - bb.lower
  mid = bb.mid
  onBar {
    when width < sma(close, len) * 0.04 && close > mid && rising(close, 2): long()
    when close < mid || width > sma(close, len) * 0.12: flat()
  }
  onPosition {
    when close >= bb.upper: flat()
  }
}
