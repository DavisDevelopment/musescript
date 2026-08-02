template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A02_FLAGSHIP_RegimeGatedMomentum {
  fast = ema(close, 13)
  slow = ema(close, 45)
  gate = sma(close, 34)
  m = macd(close, 8, 21, 5)
  Stop(0.04)
  onBar {
    when (fast > slow || rising(m.hist, 3)) && close > gate && rising(slow, 1) && close > fast && m.hist > 0: long()
    when crossunder(fast, slow) || close < gate || falling(m.hist, 3, 5): flat()
  }
}
