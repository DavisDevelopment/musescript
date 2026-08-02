// Custom indicator: blends momentum / calm / thrust into a bullish regime score.
// `indicator function` args are untyped in the grammar (typed params fail to parse).

indicator function regimeScore(_look) {
  xs = window(close, 21)
  rets = sci_diff(xs)
  bull = avg(rets)
  calm = -stat_stddev(xs)
  thrust = mom(close, 8)
  probs = ml_softmax([bull, calm, thrust])
  // Component 0 = bullish mass after softmax.
  return probs[0]
}
