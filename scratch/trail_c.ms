strategy TrailC {
  onBar {
    when close > sma(close, 5): long()
    when trail(atr(14)): flat()
  }
}
