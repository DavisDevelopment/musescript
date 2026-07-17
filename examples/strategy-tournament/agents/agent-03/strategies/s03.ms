strategy RocMacdRide {
  onBar {
    m = macd(close, 8, 21, 5)
    r = roc(close, 5)
    when m.hist > 0 || r > 0: long()
    when m.hist < 0 && r < 0: flat()
  }
}
