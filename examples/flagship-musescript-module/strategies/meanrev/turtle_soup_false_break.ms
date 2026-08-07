// Mean-reversion #27 — "Turtle Soup": a longer-horizon (55-bar) low gets
// undercut intrabar, but the bar CLOSES back above it — a same-bar reversal
// pattern, not a multi-bar bounce like the Donchian variant (#6, 20-bar,
// confirms on the FOLLOWING bar instead). Different window, different
// confirmation timing, different bar-count on the fade — a distinct trade.

strategy TurtleSoupFalseBreak {
  priorLow = lowest(low, 55)
  onBar {
    when low <= priorLow && close > priorLow: long()
    when rising(close, 5): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 7: flat()
  }
}
