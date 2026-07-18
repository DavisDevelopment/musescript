
strategy MaCross {
  param fast: Window = 10
  param slow: Window = 21
  maFast = sma(close, fast)
  maSlow = sma(close, slow)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}