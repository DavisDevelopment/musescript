strategy SoftmaxRegimePick {
  param look: Window = 21
  xs = window(close, look)
  bull = avg(sci_diff(xs))
  calm = -stat_stddev(xs)
  thrust = mom(close, 8)
  probs = ml_softmax([bull, calm, thrust])
  onBar {
    when probs[0] > probs[1] && probs[0] > probs[2] && rising(close, 2): long()
    when probs[1] >= probs[0] || falling(close, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
