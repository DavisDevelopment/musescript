strategy A03S01_MacdRisingEntryR8 {
  m = macd(close, 5, 13, 8)
  onBar {
    when rising(m.hist, 3) && m.hist > 0: long()
    when m.hist < 0 || crossunder(m.macd, m.signal): flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
