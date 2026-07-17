template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A01S03_Ema821RiseR8 {
  fast = ema(close, 8)
  slow = ema(close, 21)
  spread = fast - slow
  m = macd(close, 8, 21, 5)
  Stop(0.06)
  onBar {
    when (fast > slow && rising(spread, 2)) || (close > fast && rising(m.hist, 3)): long()
    when crossunder(fast, slow) || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 21: flat()
  }
}
