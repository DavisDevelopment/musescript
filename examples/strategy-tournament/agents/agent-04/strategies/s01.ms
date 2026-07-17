strategy Rsi13Ema34Dip {
  r = rsi(close, 13)
  trend = ema(close, 34)
  onBar {
    when position() == 0 && close > trend && r < 42: long()
    when position() != 0 && (r > 65 || close < trend): flat()
  }
}
