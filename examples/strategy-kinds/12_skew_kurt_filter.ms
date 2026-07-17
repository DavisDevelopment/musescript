strategy SkewKurtFilter {
  param look: Window = 34
  rets = sci_diff(window(close, look))
  sk = stat_skewness(rets)
  ku = stat_kurtosis(rets)
  onBar {
    when sk > 0 && ku < 2 && rising(close, 2): long()
    when sk < 0 || ku > 4: flat()
  }
  onPosition {
    when bars_in_trade >= look: flat()
  }
}
