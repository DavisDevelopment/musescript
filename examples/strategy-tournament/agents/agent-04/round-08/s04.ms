template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A04S04_RsiMeanMomentumR8 {
  r = rsi(close, 8)
  m = macd(close, 8, 21, 5)
  Stop(0.07)
  onBar {
    when r < 55 || (r < 65 && rising(m.hist, 3)): long()
    when r > 75 || m.hist < 0: flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
