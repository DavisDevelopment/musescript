// Mean-reversion #9 — Williams %R, built by hand from highest/lowest (no native
// williams_r builtin). %R = (highestHigh - close) / (highestHigh - lowestLow).
// Close to Stochastic in spirit but unsmoothed and inverted-scale — reacts to
// raw N-bar range position, not a smoothed %K/%D pair.

strategy WilliamsRStyle {
  hh = highest(high, 14)
  ll = lowest(low, 14)
  wr = (hh - close) / (hh - ll)
  onBar {
    when wr > 0.85: long()
    when wr < 0.50: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
