// Mean-reversion #26 — RMA (Wilder's smoothing, the same decay used internally
// by RSI/ATR) deviation reversion. Distinct lag/decay characteristic from the
// EMA-based (#5/#14) and SMA-based (#11/#12/#15) anchors — RMA reacts slower
// than EMA at the same window but faster than SMA of an equivalent "effective"
// length, so the same % deviation threshold fires at meaningfully different
// moments than its EMA/SMA cousins on the same tape.

strategy RmaDeviation {
  anchor = rma(close, 21)
  pctBelow = (anchor - close) / anchor
  onBar {
    when pctBelow > 0.05: long()
    when close > anchor: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 9: flat()
  }
}
