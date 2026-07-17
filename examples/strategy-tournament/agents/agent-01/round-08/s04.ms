template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A01S04_Ema834GateR8 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  gate = sma(close, 21)
  spread = fast - slow
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when (fast > slow || close > fast) && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }
  onPosition {
    when falling(spread, 3, 5) || falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
