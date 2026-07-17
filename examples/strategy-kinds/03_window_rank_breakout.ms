strategy WindowRankBreakout {
  param look: Window = 34
  param pctGate: Scalar = 80.0
  xs = window(close, look)
  rankPct = stat_percentile_rank(xs, close)
  ranked = sort(xs)
  onBar {
    when rankPct >= pctGate && close >= ranked[look - 1]: long()
    when rankPct < 40: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
