strategy DualOr {
  onBar { e8 = ema(close, 8); e34 = ema(close, 34)
    when (high >= highest(high, 21)) || (e8 > e34 && high >= highest(high, 13)): long()
    when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}