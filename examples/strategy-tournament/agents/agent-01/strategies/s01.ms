strategy S01_Sma813 {
  maFast = sma(close, 8)
  maSlow = sma(close, 13)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}
