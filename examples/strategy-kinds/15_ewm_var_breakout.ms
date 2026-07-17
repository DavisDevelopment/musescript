strategy EwmVarBreakout {
  param len: Window = 21
  v = ewm_var(close, len)
  base = stat_variance(window(close, len))
  onBar {
    when v < base * 0.85 && rising(close, 2): long()
    when v > base || falling(close, 3, 5): flat()
  }
  onPosition {
    when bars_in_trade >= len: flat()
  }
}
