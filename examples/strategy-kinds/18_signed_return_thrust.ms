strategy SignedReturnThrust {
  param look: Window = 21
  rets = sci_diff(window(close, look))
  onBar {
    when sum(rets) > atr(close, 13) && count(rets) >= look - 1 && rising(close, 2): long()
    when sum(rets) < 0: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
