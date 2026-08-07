// Mean-reversion #8 — Stochastic %K/%D crossover from oversold territory.
// Distinct from #7: entry needs a CROSSOVER confirmation (K turning back above
// D) rather than a raw threshold touch, trading immediacy for fewer whipsaws.

strategy StochKdCross {
  st = stoch(14, 3, 3)
  onBar {
    when st.k < 25 && crossover(st.k, st.d): long()
    when st.k > 60 || crossunder(st.k, st.d): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
