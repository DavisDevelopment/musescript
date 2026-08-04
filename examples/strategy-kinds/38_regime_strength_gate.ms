strategy RegimeStrengthGate {
  // Magnitude-carrying regime gates: trend STRENGTH (slope), not-overextended (zscore_roll),
  // and near the top of its own range (percent_rank) — all scale-free.
  onBar {
    when slope(close, 21) > 0 && zscore_roll(close, 21) < 2 && percent_rank(close, 55) > 0.6: long()
    when slope(close, 21) < 0 || zscore_roll(close, 21) < -1: flat()
  }
}
