strategy Adaptive {
  onBar {
    when asset_in("crypto", "forex") && slope(close, 21) > 0
         && count_true(close > sma(close, 21), zscore_roll(close, 34) > 0, percent_rank(close, 55) > 0.7) >= 2:
      long()
  }
  onPosition {
    when trail(2.5 * atr(close, 14)) || return_since_entry() > 0.08: flat()
  }
}
