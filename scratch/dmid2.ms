strategy DMid2 {
  d = donchian(20)
  onBar {
    when d.mid > d.upper + 0.0001 || d.mid < d.lower - 0.0001: long()
    when close < -1: flat()
  }
}
