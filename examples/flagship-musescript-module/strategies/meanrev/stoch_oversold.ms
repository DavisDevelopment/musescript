// Mean-reversion #7 — Stochastic oscillator oversold: %K below 20, exit on
// reversion to the midline. Oscillator is bounded [0,100] by construction
// (unlike RSI's smoothing), so it reacts faster to recent-range extremes.

strategy StochOversold {
  st = stoch(14, 3, 3)
  onBar {
    when st.k < 20: long()
    when st.k > 50: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
