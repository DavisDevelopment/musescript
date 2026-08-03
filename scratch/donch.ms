strategy DonchTest {
  onBar {
    when high >= donchian(20).upper && any_of(close > sma(close, 8), close > ema(close, 21)): long()
    when all_of(close < donchian(10).lower, close < sma(close, 5)): flat()
  }
}
