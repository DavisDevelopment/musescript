// Mean-reversion #20 — raw momentum extreme, ATR-normalized (mom() is a price
// difference, not a percentage, so it needs the same scale correction as the
// MACD-histogram variant). Distinct lookback/shape from ROC (#19): shorter
// window, and requires a rising-confirmation bar rather than a bare threshold —
// a slower trigger that waits for the first sign of deceleration.

strategy MomExtremeReversion {
  mo = mom(close, 6)
  a = atr(close, 14)
  moAtr = mo / a
  onBar {
    when moAtr < -1.8 && rising(mo, 1): long()
    when moAtr > -0.3: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 6: flat()
  }
}
