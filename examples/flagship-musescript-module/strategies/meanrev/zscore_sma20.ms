// Mean-reversion #11 — statistical z-score of price vs its own 20-bar mean,
// scaled by rolling stdev. The textbook stat-arb single-name reversion signal:
// buy when price is a large negative number of standard deviations from its
// recent mean, exit once it reverts to the mean.

strategy ZscoreSma20 {
  m = sma(close, 20)
  sd = stdev(close, 20)
  z = (close - m) / sd
  onBar {
    when z < -2.0: long()
    when z > 0.0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
