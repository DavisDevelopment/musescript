// Mean-reversion #19 — rate-of-change extreme: ROC is already a percentage
// (scale-invariant across price levels, unlike raw momentum), so this reads
// directly as "down N% over the lookback, expect a bounce" with no ATR
// normalization needed — the simplest possible extreme-move reversion signal.

strategy RocExtreme {
  r = roc(close, 10)
  onBar {
    when r < -8.0: long()
    when r > -1.0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 7: flat()
  }
}
