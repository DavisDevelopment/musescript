template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A01S01_Ema513HistR8 {
  fast = ema(close, 5)
  slow = ema(close, 13)
  gate = ema(close, 21)
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when (fast > slow || crossover(fast, slow)) && close > gate: long()
    when crossunder(fast, slow) || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
