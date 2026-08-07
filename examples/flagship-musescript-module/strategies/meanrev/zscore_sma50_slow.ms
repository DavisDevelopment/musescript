// Mean-reversion #12 — same z-score mechanism as #11 but on a much slower clock:
// 50-bar mean/stdev, shallower entry threshold, longer hold. Distinct regime:
// this targets multi-week dislocations, not multi-day ones — genuinely different
// holding-period edge from the fast z-score variant, not just a param tweak in
// isolation (the exit target and hold budget both scale with it too).

strategy ZscoreSma50Slow {
  m = sma(close, 50)
  sd = stdev(close, 50)
  z = (close - m) / sd
  onBar {
    when z < -1.5: long()
    when z > 0.5: flat()
  }
  onPosition {
    when unrealized_pnl < -0.07 * equity: flat()
    when bars_in_trade >= 20: flat()
  }
}
