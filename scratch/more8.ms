strategy More8 {
  onBar {
    when asset_in("crypto", "forex") && slope(close, 21) > 0 && zscore_roll(close, 21) > -2 && percent_rank(close, 34) > 0.4: long()
    when return_since_entry() > 0.08 || close < lowest_since_entry("low"): flat()
    when highest_since_entry("high") > 0 && slope(close, 8) < 0: flat()
  }
}
