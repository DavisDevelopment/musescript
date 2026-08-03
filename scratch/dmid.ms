strategy DMid {
  onBar {
    when donchian(20).mid > donchian(20).upper + 0.0001 || donchian(20).mid < donchian(20).lower - 0.0001: long()
    when close < -1: flat()
  }
}
