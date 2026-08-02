strategy MacdRise {
  m = macd(close, 8, 21, 5)
  gate = sma(close, 34)
  onBar {
    when rising(m.hist, 3) && close > gate: long()
    when falling(m.hist, 3, 5) || close < gate: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
