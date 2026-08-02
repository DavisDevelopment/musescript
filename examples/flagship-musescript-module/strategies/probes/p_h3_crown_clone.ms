// H3 — faithful agent-04 R6 s05 under causal costs (uses stitched lib templates).

strategy ProbeCrownClone {
  r13 = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  fast = ema(close, 13)
  anchor = ema(close, 34)

  onBar {
    when close > e8 && donchHigh(21): long()
    when crownExit(13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()
    when bars_in_trade >= 5 && falling(r13, 3): flat()
  }
}
