strategy Rsi13Ema55Stop {
  r = rsi(close, 13)
  trend = ema(close, 55)
  onBar {
    when position() == 0 && close > trend && r < 42: long()
    when position() != 0 && (r > 68 || close < trend): flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
  }
}
