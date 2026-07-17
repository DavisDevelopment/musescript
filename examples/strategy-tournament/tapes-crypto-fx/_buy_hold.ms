strategy BuyHold {
  onBar { when bar_index == 0: long() }
}
