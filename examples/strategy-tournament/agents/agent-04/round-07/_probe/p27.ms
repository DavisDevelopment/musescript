strategy P27 {
  r13 = rsi(close, 13)
  r8 = rsi(close, 8)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r13 < 42 && r8 < 45: long()
    when r13 > 55 || r8 > 58 || vol > 0.025: flat()
  }
  onPosition {
    when unrealized_pnl < -0.016 * equity: flat()
    when bars_in_trade >= 5 && falling(r13, 3, 3) && r13 < 52: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.012 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
