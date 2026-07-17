template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A04S02_RsiBroadR8 {
  r = rsi(close, 8)
  m = macd(close, 5, 13, 8)
  Stop(0.06)
  onBar {
    when r < 60 && rising(m.hist, 2): long()
    when r > 70 || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when falling(m.hist, 3, 5): flat()
  }
}
