// Reusable risk kit: hard equity stop + time stop + profit lock.
// Expanded via `use RiskKit(...)` inside the strategy body.

module RiskKit(
  stopPct: Scalar = 0.05,
  timeBars: Window = 13,
  lockBars: Window = 8,
  lockPct: Scalar = 0.03
) {
  onPosition {
    when unrealized_pnl < -stopPct * equity: flat()
    when bars_in_trade >= timeBars: flat()
    when bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity: flat()
  }
}

template SoftStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}
