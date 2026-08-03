strategy TrailProbe {
  onBar {
    when close > sma(close, 8): long()
    when close < highest(high, bars_in_trade()) - 2 * atr(14): flat()
  }
}
