strategy DictScorecard {
  param look: Window = 21
  xs = window(close, look)
  reg = stat_regression(xs)
  m = macd(close)
  onBar {
    scores = dict_new()
    dict_set(scores, "slope", reg.slope)
    dict_set(scores, "r2", reg.r2)
    dict_set(scores, "hist", m.hist)
    when dict_get(scores, "r2", 0) > 0.25
      && dict_get(scores, "slope", 0) > 0
      && dict_get(scores, "hist", 0) > 0: long()
    when dict_get(scores, "hist", 0) < 0 || dict_size(scores) < 3: flat()
  }
}
