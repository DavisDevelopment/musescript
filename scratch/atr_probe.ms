strategy AtrProbe {
  onBar {
    when close > sma(close, 5): long()
    when atr(14) > 0 && bars_in_trade() > 2: flat()
  }
}
