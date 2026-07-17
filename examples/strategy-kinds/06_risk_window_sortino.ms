strategy RiskWindowSortino {
  param look: Window = 21
  param minSortino: Scalar = -2.0
  px = window(close, look)
  rets = sci_diff(px)
  s = sortino(rets)
  dd = max_drawdown(sci_normalize(px))
  onBar {
    when rising(close, 2) && close > sma(close, look) && s > minSortino: long()
    when falling(close, 3, 5) || dd > 0.35: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
    when s < minSortino - 1.0: flat()
  }
}
