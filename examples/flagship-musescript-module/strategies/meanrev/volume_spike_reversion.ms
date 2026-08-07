// Mean-reversion #22 — capitulation-volume reversion: a down bar on volume well
// above its recent average is read as forced/panic selling rather than
// information-driven selling, which tends to exhaust quickly. The only strategy
// in this set that conditions on volume at all — a genuinely separate data axis
// from every price/oscillator-only variant above.

strategy VolumeSpikeReversion {
  volAvg = sma(volume, 20)
  volRatio = volume / volAvg
  b = candle_body(0)
  onBar {
    when volRatio > 2.0 && b < -0.01: long()
    when rising(close, 2): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 5: flat()
  }
}
