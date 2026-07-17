strategy Donchian13x5 {
  onBar {
    when high >= highest(high, 13): long()
    when low <= lowest(low, 5): flat()
  }
}
