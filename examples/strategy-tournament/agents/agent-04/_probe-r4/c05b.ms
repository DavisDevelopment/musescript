strategy S05RsiRecovery {
  onBar {
    r = rsi(close, 8)
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    when e8 > e34 && r > 35 && r[1] <= 35: long()
    when low <= lowest(low, 13) || r > 62 || e8 < e34: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
