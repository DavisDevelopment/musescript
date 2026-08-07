// Mean-reversion #16 — gap fade: a large ATR-normalized down-gap tends to partly
// fill. Event-driven mechanism (triggers on a single bar's open-vs-prior-close
// jump), not a multi-bar oscillator/band — genuinely different signal timing
// from everything else in this set, which all need several bars of history to
// even compute.

strategy GapFade {
  g = candle_gap(0)
  onBar {
    when g < -1.2: long()
    when g > -0.2: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 4: flat()
  }
}
