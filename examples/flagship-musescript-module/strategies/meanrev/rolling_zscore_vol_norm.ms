// Mean-reversion #25 — adaptive rolling z-score via the engine's own
// vol-normalized primitive (zscore_roll), rather than hand-building mean/stdev
// like #11/#12. Shorter window than either of those, tuned for a faster,
// choppier signal — the engine-native implementation may also differ subtly
// from the hand-rolled version (different internal windowing/edge handling),
// which is itself a useful cross-check between the two approaches.

strategy RollingZscoreVolNorm {
  z = zscore_roll(close, 15)
  onBar {
    when z < -1.8: long()
    when z > -0.2: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 7: flat()
  }
}
