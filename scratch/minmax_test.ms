strategy MinMaxTest {
  param slow = 21 { min: 13, max: 34, step: 7 }
  onBar {
    when close > sma(close, slow): long()
    when close < sma(close, slow): flat()
  }
}
