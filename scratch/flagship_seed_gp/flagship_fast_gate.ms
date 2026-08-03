strategy FlagshipFastGate {
  fast = ema(close, 8)
  slow = ema(close, 34)
  gate = sma(close, 21)
  onBar {
    when fast > slow && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }
}
