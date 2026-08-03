strategy FibListSweep {
  param fast = 8 { values: [5, 8, 13] }
  param slow = 34 { values: [21, 34, 55] }
  onBar {
    when close > sma(close, fast) && close > sma(close, slow): long()
    when close < sma(close, slow): flat()
  }
}
