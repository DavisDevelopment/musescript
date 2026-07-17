strategy Don13 {
  onBar { when high >= highest(high, 13): long(); when low <= lowest(low, 8): flat() }
  onPosition { when bars_in_trade >= 8: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}