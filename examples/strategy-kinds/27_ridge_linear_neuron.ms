strategy RidgeLinearNeuron {
  param look: Window = 13
  xs = window(mom(close, 5), look)
  ys = window(roc(close, 1), look)
  w = ml_ridge_fit(xs, ys, 1, 0.01)
  pred = ml_linear_predict([mom(close, 5)], w)
  gate = ml_sigmoid(pred)
  onBar {
    when gate > 0.55 && rising(close, 2): long()
    when gate < 0.45 || falling(close, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
