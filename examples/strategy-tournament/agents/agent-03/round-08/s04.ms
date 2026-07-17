strategy A03S04_Macd821R8 {
  m = macd(close, 8, 21, 5)
  onBar {
    when rising(m.hist, 3) && m.hist > 0: long()
    when m.hist < 0 || crossunder(m.macd, m.signal): flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.06 * equity: flat()
  }
}
