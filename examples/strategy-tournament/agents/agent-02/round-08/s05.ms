template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A02S05_EmaRiskShellR8 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trail = ema(close, 13)
  m = macd(close, 8, 21, 5)
  Stop(0.04)
  onBar {
    when (fast > slow && rising(fast - slow, 2)) || (close > fast && rising(m.hist, 3)): long()
    when close < trail || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when falling(m.hist, 3, 5): flat()
  }
}
