strategy Atr1 {
  onBar {
    when atr(14) > 0 && close > sma(close, 5): long()
    when close < sma(close, 5): flat()
  }
}
