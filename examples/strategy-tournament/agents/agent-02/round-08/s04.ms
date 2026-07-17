template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A02S04_EmaCrossOrHistR8 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when fast > slow || rising(m.hist, 3): long()
    when crossunder(fast, slow) || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
