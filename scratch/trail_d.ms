strategy TrailD {
  onBar {
    when close > sma(close, 5): long()
    when trail(1 * atr(14)): flat()
  }
}
