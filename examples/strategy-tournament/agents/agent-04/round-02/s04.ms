strategy RsiRecoveryEma813 {
  r = rsi(close, 8)
  fast = ema(close, 8)
  slow = ema(close, 13)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && close > trend && r > 35 && r[1] <= 35: long()
    when position() != 0 && (r > 62 || crossunder(fast, trend)): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
