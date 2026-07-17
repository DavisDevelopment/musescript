// Fat-arrow lambdas on the typed surface (desugar to the same EFunction as function(...)).

strategy ArrowLambdas {
  param look: Window = 13

  onBar {
    rets = sci_diff(window(close, look))
    ups = filter(rets, r => r > 0)
    spreads = zipWith(
      window(ema(close, 8), look),
      window(ema(close, 21), look),
      (a, b) => a - b
    )
    when count(ups) > 6 && avg(spreads) > 0: long()
    when count(ups) < 4: flat()
  }
}
