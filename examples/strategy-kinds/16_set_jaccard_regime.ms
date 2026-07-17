strategy SetJaccardRegime {
  param fast: Window = 8
  param slow: Window = 21
  m = macd(close)
  bb = bbands(close, slow, 2.0)
  onBar {
    bull = set_new()
    bear = set_new()
    when m.hist > 0: set_add(bull, "hist")
    when close > ema(close, fast): set_add(bull, "ema")
    when close < bb.upper: set_add(bull, "band")
    when m.hist < 0: set_add(bear, "hist")
    when close < ema(close, fast): set_add(bear, "ema")
    when close > bb.lower: set_add(bear, "band")
    when set_jaccard(bull, set_new()) < 1 && set_size(bull) >= 2 && set_jaccard(bull, bear) < 0.34: long()
    when set_size(bear) >= 2 || set_jaccard(bull, bear) > 0.66: flat()
  }
}
