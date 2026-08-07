// Mean-reversion #15 — moving-average % envelope: a fixed percentage band around
// a plain SMA (no volatility scaling at all, unlike ATR/stdev-based bands above).
// The oldest, crudest mean-reversion mechanism in this set — included precisely
// because it's a meaningfully different bet: a static % band reacts to a genuine
// price dislocation the same way in calm and violent markets alike, where every
// other strategy here adapts its trigger to recent volatility.

strategy MaEnvelope {
  m = sma(close, 20)
  pctBelow = (m - close) / m
  onBar {
    when pctBelow > 0.06: long()
    when close > m: flat()
  }
  onPosition {
    when unrealized_pnl < -0.06 * equity: flat()
    when bars_in_trade >= 10: flat()
  }
}
