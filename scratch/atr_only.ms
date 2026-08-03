strategy AtrOnly {
  onBar {
    when bar_index == 20: long()
    when atr(14) > 0: flat()
  }
}
