strategy BS {
  onBar {
    when bars_since(candle_dir(0) != 0) == 0: long()
    when bars_since(candle_dir(0) != 0) > 0: flat()
  }
}
