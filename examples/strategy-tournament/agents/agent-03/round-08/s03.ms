strategy A03S03_MacdTrendGateR8 {
  m = macd(close, 5, 13, 8)
  trend = ema(close, 8)
  onBar {
    when rising(m.hist, 3) && m.hist > 0 && close > trend: long()
    when m.hist < 0 || crossunder(m.macd, m.signal) || close < trend: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
