strategy DotMseConfidence {
  param look: Window = 21
  xs = window(close, look)
  ys = window(sma(close, 8), look)
  align = ml_dot(sci_normalize(xs), sci_normalize(ys))
  drift = ml_mse(xs, ys)
  onBar {
    when align > 0 && drift < avg(xs) * 0.002 && rising(close, 2): long()
    when align < 0 || drift > avg(xs) * 0.01: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
