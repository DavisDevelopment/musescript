strategy PipeStrat {
  param fast: Window = 10 { min: 5, max: 13, step: 3, tune: grid }
  param slow: Window = 30 { min: 21, max: 34, step: 13, tune: grid }
  onBar {
    a = sma(close, fast)
    b = sma(close, slow)
    when crossover(a, b): long()
    when crossunder(a, b): flat()
  }
}
pipeline Discover {
  walkforward(2, 3)
  promote((r) => r.sharpe > -999.0)
  tune(fast, slow)
  optimize(sharpe)
}
