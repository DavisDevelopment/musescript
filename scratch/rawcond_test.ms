strategy RawCondTest {
  onBar {
    when (ema(close,13) > ema(close,45) || rising(macd(close, 8, 21, 5).hist, 3)) && close > sma(close,34) && rising(ema(close,45), 1) && close > ema(close,13) && macd(close,8,21,5).hist > 0: long()
    when crossunder(ema(close,13), ema(close,45)) || close < sma(close,34) || falling(macd(close,8,21,5).hist, 3, 5): flat()
  }
}
