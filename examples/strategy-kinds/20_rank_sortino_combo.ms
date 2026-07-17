strategy RankSortinoCombo {
  param look: Window = 21
  xs = window(close, look)
  rets = sci_diff(xs)
  pct = stat_percentile_rank(xs, close)
  s = sortino(rets)
  onBar {
    when pct >= 70 && s > 0.5 && close > sma(close, look): long()
    when pct < 40 || s < 0: flat()
  }
  onPosition {
    when max_drawdown(sci_normalize(xs)) > 0.2: flat()
  }
}
