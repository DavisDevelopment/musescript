// Mean-reversion #21 — regime-gated RSI reversion. No native ADX builtin, so
// trend strength is proxied honestly by range-expansion: 20-bar high-low range
// versus what 20 bars of average true range would imply. A low ratio means the
// market spent the window going nowhere (choppy/ranging) — exactly the regime
// where reversion trades have historically worked best and trend-following
// hasn't. High ratio (real trend) disables new entries entirely.

strategy AdxGatedReversion {
  r = rsi(close, 14)
  rangeSpan = highest(high, 20) - lowest(low, 20)
  impliedRange = atr(close, 20) * 20
  chopRatio = rangeSpan / impliedRange
  onBar {
    when r < 30 && chopRatio < 2.2: long()
    when r > 55 || chopRatio > 3.5: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 9: flat()
  }
}
