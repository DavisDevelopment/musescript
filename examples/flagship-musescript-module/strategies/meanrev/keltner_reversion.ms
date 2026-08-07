// Mean-reversion #5 — Keltner Channel: EMA +/- ATR multiple (volatility-scaled
// band, unlike Bollinger's stdev-scaled band). Distinct band construction from
// #3/#4 — ATR bands react differently to volatility clustering than stdev bands.

strategy KeltnerReversion {
  mid = ema(close, 20)
  band = 2.0 * atr(close, 20)
  onBar {
    when close < mid - band: long()
    when close > mid: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
