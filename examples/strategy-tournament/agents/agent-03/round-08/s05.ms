strategy A03S05_DualMacdR8 {
  m = macd(close, 5, 13, 8)
  s = macd(close, 13, 34, 8)
  onBar {
    when rising(m.hist, 3) && (m.hist > 0 || s.hist > 0): long()
    when m.hist < 0 && s.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when crossunder(m.macd, m.signal): flat()
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
