// Mean-reversion #24 — percentile-rank reversion: buy when the current close
// sits in the bottom decile of its own trailing distribution, exit once it's
// back above the median. Rank-based, not distance-based like the z-score
// variants (#11/#12) — immune to fat-tailed outliers skewing a mean/stdev
// estimate, at the cost of being blind to HOW far below the pack price is.

strategy PercentRankReversion {
  pr = percent_rank(close, 50)
  onBar {
    when pr < 10.0: long()
    when pr > 50.0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 12: flat()
  }
}
