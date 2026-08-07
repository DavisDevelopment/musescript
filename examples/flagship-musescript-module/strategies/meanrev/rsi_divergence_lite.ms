// Mean-reversion #23 — bullish-divergence-lite: price is still falling (making
// lower lows) but RSI is no longer confirming (it's turned up), a classic
// leading-indicator setup. Genuinely different information from a bare RSI
// threshold (#2/#1) — this can trigger even when RSI never got statistically
// "oversold" at all, purely off the disagreement between price and momentum.

strategy RsiDivergenceLite {
  r = rsi(close, 14)
  onBar {
    when falling(close, 5) && rising(r, 3): long()
    when falling(r, 2): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
