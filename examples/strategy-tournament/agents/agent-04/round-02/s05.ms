strategy RsiCrossDonchianTime {
  r = rsi(close, 8)
  fast = ema(close, 8)
  slow = ema(close, 34)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && close > trend && fast > slow && r > 35 && r[1] <= 35: long()
    when position() != 0 && (low <= lowest(low, 13) || r > 65 || close < trend): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
