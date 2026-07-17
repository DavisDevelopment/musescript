strategy Squeeze821Donchian {
  atrFast = atr(close, 8)
  atrSlow = atr(close, 21)
  onBar {
    when atrFast < atrSlow * 0.98 && high >= highest(high, 21): long()
    when low <= lowest(low, 8): flat()
  }
}
