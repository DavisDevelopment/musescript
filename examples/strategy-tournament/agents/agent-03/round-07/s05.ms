template HardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}
strategy MacdRisingCascadeExit {
  m = macd(close, 8, 21, 5)
  HardStop(0.08)
  onBar {
    when rising(m.hist, 2) && m.hist > 0: long()
    when m.hist < 0 || crossunder(m.macd, m.signal): flat()
  }
  onPosition {
    when falling(m.hist, 3, 8): flat()
  }
}
