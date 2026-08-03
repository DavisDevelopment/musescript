strategy CoercePlain {
  onBar {
    when close > sma(close, 5): long()
    when close < sma(close, 5): flat()
  }
}
