strategy RsiDipTimeStop {
  r = rsi(close, 13)
  trend = ema(close, 21)
  onBar {
    when position() == 0 && close > trend && r < 42: long()
    when position() != 0 && (r > 65 || close < trend): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
