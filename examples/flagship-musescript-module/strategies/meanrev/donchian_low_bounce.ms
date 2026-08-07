// Mean-reversion #6 — Donchian low bounce: the inverse of a breakout system.
// Standard Donchian strategies BUY the N-bar high (trend-follow); this buys the
// N-bar LOW with a one-bar reversal confirmation (today higher than yesterday),
// betting the low holds rather than extends. Exit at the channel midline.

strategy DonchianLowBounce {
  d = donchian(20)
  onBar {
    when low <= d.lower && rising(close, 1): long()
    when close > d.mid: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 10: flat()
  }
}
