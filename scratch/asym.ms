strategy Asym {
  param fast = 8 { values: [3, 5, 8, 13] }
  param slow = 34 { values: [34, 55] }
  onBar {
    when close > sma(close, fast) && close > sma(close, slow): long()
    when close < sma(close, slow): flat()
  }
}
