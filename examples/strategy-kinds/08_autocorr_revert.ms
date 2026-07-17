strategy AutocorrRevert {
  param look: Window = 34
  param lag: Window = 2
  xs = window(close, look)
  ac = stat_autocorr(xs, lag)
  onBar {
    when ac > 0.4 && falling(close, 2): long()
    when ac < 0.1 || rising(close, 3): flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
