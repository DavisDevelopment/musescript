strategy BuyHold {
  onBar {
    when bar_index == 1: long()
  }
}
