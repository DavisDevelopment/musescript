template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeRsiScalp {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 8) / close
  onBar {
    when position() == 0 && vol < 0.012 && r13 < 40 && r8 > r8[1]: long()
    when r13 > 50 || r8 > 55: flat()
  }
  EquityHardStop(0.015)
  onPosition {
    when bars_in_trade >= 5 && falling(r13, 2, 3): flat()
    when bars_in_trade >= 8: flat()
  }
}
