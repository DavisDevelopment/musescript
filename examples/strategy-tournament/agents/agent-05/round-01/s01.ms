strategy Donchian21x8 {
  onBar {
    when high >= highest(high, 21): long()
    when low <= lowest(low, 8): flat()
  }
}
