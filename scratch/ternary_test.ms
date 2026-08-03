strategy TernaryOpaqueTest {
  onBar {
    when ((rising(macd(close, 8, 21, 5).hist, 3)) ? 1.0 : 0.0) > 0.5: long()
    when close < sma(close, 20): flat()
  }
}
