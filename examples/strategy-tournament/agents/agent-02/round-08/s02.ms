template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A02S02_Ema821FastR8 {
  fast = ema(close, 8)
  slow = ema(close, 21)
  gate = ema(close, 34)
  m = macd(close, 5, 13, 8)
  Stop(0.06)
  onBar {
    when fast > slow && (close > gate || rising(m.hist, 3)): long()
    when crossunder(fast, slow) || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 21: flat()
  }
}
