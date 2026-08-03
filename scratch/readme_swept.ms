strategy Swept {
  param slow = 34 { min: 21, max: 55, step: 1 }
  param fast = 8  { values: [5, 8, 13, 21] }
  onBar {
    when close > sma(close, fast) && close > sma(close, slow): long()
    when close < sma(close, slow): flat()
  }
}
