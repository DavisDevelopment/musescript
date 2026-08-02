// Mode mass: sticky / thrust / crown / bounce — arg untyped (indicator function grammar).

indicator function modeMasses(_look) {
  xs = window(close, 21)
  rets = sci_diff(xs)
  trend = avg(rets)
  calm = -stat_stddev(xs)
  thrust = mom(close, 13) / (atr(close, 13) + 0.0001)
  bounce = -rsi(close, 5)
  return ml_softmax([trend + calm, thrust, trend, bounce])
}
