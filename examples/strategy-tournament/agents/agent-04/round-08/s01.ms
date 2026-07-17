template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A04S01_RsiDipHistR8 {
  r = rsi(close, 13)
  m = macd(close, 5, 13, 8)
  trend = ema(close, 8)
  Stop(0.06)
  onBar {
    when r < 55 && close > trend && m.hist > -0.001: long()
    when r > 65 || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
