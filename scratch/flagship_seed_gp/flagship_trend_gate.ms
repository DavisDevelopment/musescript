strategy FlagshipTrendGate {
  fast = ema(close, 13)
  slow = ema(close, 45)
  gate = sma(close, 34)
  onBar {
    when fast > slow && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }
}
