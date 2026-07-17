strategy SignalSetCompose {
  param fast: Window = 8
  param slow: Window = 21
  m = macd(close)
  bb = bbands(close, slow, 2.0)
  onBar {
    tags = set_new()
    when m.hist > 0: set_add(tags, "hist_up")
    when rising(ema(close, fast) - ema(close, slow), 2): set_add(tags, "spread_up")
    when close < bb.upper: set_add(tags, "inside_band")
    when set_has(tags, "hist_up") && set_has(tags, "spread_up") && set_has(tags, "inside_band"): long()
    when !set_has(tags, "hist_up") || set_size(tags) < 2: flat()
  }
}
