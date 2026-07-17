strategy StochKdCross {
  param kLen: Window = 13
  param dLen: Window = 3
  s = stoch(kLen, dLen, 3)
  onBar {
    when crossover(s.k, s.d) && s.k < 30: long()
    when crossunder(s.k, s.d) || s.k > 80: flat()
  }
  onPosition {
    when s.d > 75: flat()
  }
}
