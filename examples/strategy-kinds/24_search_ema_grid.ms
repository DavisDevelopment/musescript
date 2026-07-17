pipeline discover {
  sample(universe, 8);
  tune(fast, slow);
  optimize(sharpe, [fast, slow]);
}

strategy SearchEmaGrid {
  param fast: Window = 8
  param slow: Window = 21
  onBar {
    when crossover(ema(close, fast), ema(close, slow)): long()
    when crossunder(ema(close, fast), ema(close, slow)): flat()
  }
}
