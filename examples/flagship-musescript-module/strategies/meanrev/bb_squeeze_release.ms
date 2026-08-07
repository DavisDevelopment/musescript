// Mean-reversion #4 — Bollinger squeeze-then-poke: volatility must first be
// COMPRESSED (short-window ATR well below its longer-window average) before a
// lower-band touch counts as a real signal. Filters out band touches during
// already-wide, trending volatility, where a "poke" is more likely continuation
// than reversion. atr(short)/atr(long) is the compression proxy — both take the
// raw close series directly, so it's safe against derived-series smoothing risk.

strategy BollingerSqueezeRelease {
  bb = bbands(close, 20, 2.0)
  compressed = atr(close, 10) < 0.85 * atr(close, 30)
  onBar {
    when close < bb.lower && compressed: long()
    when close > bb.mid: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
