strategy A03S02_MacdFastProfitR8 {
  m = macd(close, 5, 13, 8)
  onBar {
    when rising(m.hist, 2) && m.hist > 0: long()
    when m.hist < 0 || crossunder(m.macd, m.signal): flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.025 * equity: flat()
    when unrealized_pnl < -0.08 * equity: flat()
  }
}
