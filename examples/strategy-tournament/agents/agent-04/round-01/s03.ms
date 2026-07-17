strategy Rsi8RecoveryEma21 {
  r = rsi(close, 8)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && close > trend && r > 35 && r[1] <= 35: long()
    when position() != 0 && (r > 62 || close < trend): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
