strategy AtrTrailingStop {
  // Peak-following ATR trailing stop (trail) + a signed open-trade return take-profit.
  param atrLen: Window = 13
  fast = ema(close, 13)
  slow = ema(close, 34)
  onBar {
    when fast > slow && close > sma(close, 55): long()
  }
  onPosition {
    when trail(2.5 * atr(close, atrLen)): flat("trail")
    when return_since_entry() > 0.15: flat("take_profit")
  }
}
