template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A04S05_DualRsiCryptoFixR8 {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  m = macd(close, 5, 13, 8)
  Stop(0.06)
  onBar {
    when (r13 < 55 && m.hist > 0) || (r8 < 45 && rising(m.hist, 2)): long()
    when r8 > 70 || r13 > 68 || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
