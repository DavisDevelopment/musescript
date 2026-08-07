// Mean-reversion #3 — Bollinger %B: price pierces the lower band, reverts to the
// middle band (the SMA the bands are built around). Pure band-touch mechanism,
// no oscillator involved — distinct signal family from the RSI variants.

strategy BollingerPercentB {
  bb = bbands(close, 20, 2.0)
  onBar {
    when close < bb.lower: long()
    when close > bb.mid: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
