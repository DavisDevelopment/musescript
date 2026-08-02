strategy AtrThrust {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when thrust < 0 || roc(close, 13) < -1: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when falling(thrust, 3, 5): flat()
  }
}
