strategy SweepTest {
  param fast = sweep(5, 8, 13)
  param slow = sweep(21, 34, 55)
  onBar {
    when close > sma(close, fast) && close > sma(close, slow): long()
    when close < sma(close, slow): flat()
  }
}
