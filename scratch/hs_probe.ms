strategy HsProbe {
  onBar {
    when close > highest(high, 5) - 0.0001: long()
    when close < lowest(low, 5): flat()
  }
}
