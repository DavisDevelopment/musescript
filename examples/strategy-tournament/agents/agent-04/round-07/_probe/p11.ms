strategy ProbeEmaPullback {
  r = rsi(close, 13)
  e21 = ema(close, 21)
  onBar {
    when position() == 0 && close > e21 && r < 42 && r > r[1]: long()
    when r > 60 || close < e21: flat()
  }
  onPosition {
    when unrealized_pnl < -0.035 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
