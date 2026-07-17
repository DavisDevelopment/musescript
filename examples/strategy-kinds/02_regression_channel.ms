strategy RegressionChannel {
  param look: Window = 21
  param minR2: Scalar = 0.35
  xs = window(close, look)
  reg = stat_regression(xs)
  onBar {
    when reg.r2 >= minR2 && reg.slope > 0 && close > sma(close, look): long()
    when reg.slope <= 0 || reg.r2 < minR2 * 0.5: flat()
  }
  onPosition {
    when falling(close, 3, 5): flat()
  }
}
