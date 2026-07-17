strategy TwoLayerToyNn {
  param look: Window = 13
  f0 = mom(close, 8) / (atr(close, look) + 0.000000001)
  f1 = (rsi(close, look) - 50.0) / 50.0
  f2 = (close - sma(close, 21)) / (atr(close, look) + 0.000000001)
  feats = [f0, f1, f2]
  h0 = ml_sigmoid(ml_dot(feats, [0.8, 0.4, 0.6]) - 0.1)
  h1 = ml_sigmoid(ml_dot(feats, [-0.3, 0.9, 0.2]) + 0.05)
  out = ml_sigmoid(ml_dot([h0, h1], [1.2, -0.7]) - 0.2)
  onBar {
    when out > 0.58 && rising(close, 2): long()
    when out < 0.42 || falling(close, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
  }
}
