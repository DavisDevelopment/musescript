strategy Rsi13Ema34Cross {
  r = rsi(close, 13)
  trend = ema(close, 34)
  onBar {
    when position() == 0 && close > trend && r < 44 && r[1] >= 44: long()
    when position() != 0 && (r > 68 || close < trend): flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
