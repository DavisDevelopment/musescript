strategy TaggedExits {
  // Labelled exits: each flat("...") records a per-tag fire count in the result JSON (exitTags),
  // so you can see which exit layers actually trigger — a silent no-op layer shows count 0/absent.
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when fast > slow && close > sma(close, 55): long()
    when crossunder(fast, slow): flat("trend_flip")
  }
  onPosition {
    when trail(2 * atr(close, 13)): flat("trail_stop")
    when bars_in_trade() >= 34: flat("time_stop")
  }
}
