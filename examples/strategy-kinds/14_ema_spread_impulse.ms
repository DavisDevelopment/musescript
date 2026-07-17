strategy EmaSpreadImpulse {
  param look: Window = 13
  spread = ema(close, 8) - ema(close, 21)
  onBar {
    when avg(window(spread, look)) > 0 && rising(close, 2): long()
    when avg(window(spread, look)) < 0: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
