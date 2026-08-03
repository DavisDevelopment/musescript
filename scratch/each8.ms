strategy Each8 {
  onBar {
    when asset_in("crypto","forex") && symbol_in("BTCUSD","ETHUSD") && slope(close,13) > 0 && zscore_roll(close,21) > -3 && percent_rank(close,34) > 0.2: long()
    when return_since_entry() > 0.1 || close > highest_since_entry("high") * 1.5 || close < lowest_since_entry("low") * 0.5: flat()
  }
}
