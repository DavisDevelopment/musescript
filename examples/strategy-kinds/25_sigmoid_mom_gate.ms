strategy SigmoidMomGate {
  param look: Window = 13
  m = mom(close, look)
  vol = atr(close, look)
  gate = ml_sigmoid(m / (vol + 0.000000001))
  onBar {
    when gate > 0.62 && rising(close, 2): long()
    when gate < 0.42 || falling(close, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
  }
}
