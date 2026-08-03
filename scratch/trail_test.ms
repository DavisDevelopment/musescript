strategy TrailStop {
  onBar {
    when close > sma(close, 8) && close > ema(close, 21): long()
    when trail(2 * atr(14)): flat()
  }
}
