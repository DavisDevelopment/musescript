strategy DvH {
  onBar {
    when donchian(20).upper > highest(high, 20) + 0.0001 || donchian(20).upper < highest(high,20) - 0.0001: long()
    when close < 0: flat()
  }
}
