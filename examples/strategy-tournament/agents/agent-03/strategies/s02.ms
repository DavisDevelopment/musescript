strategy MomMacdRide {
  onBar {
    m = macd(close, 8, 21, 5)
    p = mom(close, 8)
    when m.hist > 0 || p > 0: long()
    when m.hist < 0 && p < 0: flat()
  }
}
