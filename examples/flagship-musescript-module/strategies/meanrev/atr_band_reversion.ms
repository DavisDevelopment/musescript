// Mean-reversion #14 — plain ATR-distance-from-EMA reversion. Simpler cousin of
// the Keltner variant (#5): no channel object, just "how many ATRs is price away
// from its EMA right now" as a standalone scalar, with a shallower band and a
// tighter, faster exit — a distinct risk/reward shape, not a duplicate of #5.

strategy AtrBandReversion {
  e = ema(close, 13)
  a = atr(close, 13)
  distAtr = (close - e) / a
  onBar {
    when distAtr < -1.5: long()
    when distAtr > -0.2: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 6: flat()
  }
}
