// Mean-reversion #2 — classic RSI(14) oversold, exit at NEUTRAL (50) not overbought.
// Distinct from Connors: longer lookback, and the exit target is "reverted to
// neutral," not "now overbought" — a shorter, more conservative hold than most
// RSI systems, on the theory that most of the reversion edge is captured early.

strategy Rsi14Neutral {
  r = rsi(close, 14)
  onBar {
    when r < 30: long()
    when r > 50: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 10: flat()
  }
}
