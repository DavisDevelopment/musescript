strategy MacdHistBbands {
  param histBars: Window = 3
  param bbLen: Window = 21
  m = macd(close)
  bb = bbands(close, bbLen, 2.0)
  onBar {
    when m.hist > 0 && rising(m.hist, histBars) && close < bb.upper: long()
    when m.hist < 0 || close >= bb.upper: flat()
  }
  onPosition {
    when falling(m.hist, histBars): flat()
    when close <= bb.lower: flat()
  }
}
