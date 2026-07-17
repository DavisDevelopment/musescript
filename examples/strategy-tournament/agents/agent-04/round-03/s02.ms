strategy RsiRecoveryDonchian {
  onBar {
    r = rsi(close, 13)
    when r < 35 && high >= highest(high, 21): long()
    when r > 65 || low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
