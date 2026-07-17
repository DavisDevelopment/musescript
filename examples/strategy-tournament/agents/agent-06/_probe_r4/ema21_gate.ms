strategy EmaGate {
  onBar { when close > ema(close, 21) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}