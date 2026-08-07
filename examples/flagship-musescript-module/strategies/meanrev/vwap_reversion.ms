// Mean-reversion #13 — VWAP reversion: price stretched below the volume-weighted
// average price reverts to it. VWAP is a volume-informed anchor, distinct from
// the purely price-based SMA/EMA anchors used elsewhere in this set — it moves
// less on low-volume noise bars.

strategy VwapReversion {
  vw = vwap()
  dist = (close - vw) / vw
  onBar {
    when dist < -0.03: long()
    when close > vw: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
