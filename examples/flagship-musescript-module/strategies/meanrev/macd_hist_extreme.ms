// Mean-reversion #18 — MACD histogram extreme: when the histogram (momentum's
// second derivative) is at an unusually deep negative extreme AND starting to
// turn up, downside momentum is decelerating fastest right before price
// reversion typically shows up. Trend-indicator repurposed as a reversion
// timing tool, not used in its usual crossover-follow role.

strategy MacdHistExtreme {
  m = macd(close, 12, 26, 9)
  a = atr(close, 26)
  histAtr = m.hist / a
  onBar {
    when histAtr < -0.15 && rising(m.hist, 2): long()
    when m.hist > 0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
