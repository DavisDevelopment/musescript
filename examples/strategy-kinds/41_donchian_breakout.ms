strategy DonchianBreakout {
  // Donchian channel struct: donchian(n).upper / .lower / .mid (reads high/low implicitly).
  param n: Window = 21
  onBar {
    when high >= donchian(n).upper: long()
    when low <= donchian(13).lower: flat()
    when close < donchian(n).mid: flat()
  }
}
