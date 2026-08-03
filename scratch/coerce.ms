strategy Coerce {
  onBar {
    when count_true(close > sma(close, 5)) >= 1: long()
    when count_true(close > sma(close, 5)) < 1: flat()
  }
}
