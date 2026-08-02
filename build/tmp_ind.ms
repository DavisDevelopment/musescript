indicator function regimeScore(look) {
  xs = window(close, 21)
  rets = sci_diff(xs)
  bull = avg(rets)
  calm = -stat_stddev(xs)
  thrust = mom(close, 8)
  probs = ml_softmax([bull, calm, thrust])
  return probs[0]
}
strategy S {
  r = regimeScore(21)
  onBar { when r > 0.3 && crossover(sma(close, 8), sma(close, 21)): long() }
}
