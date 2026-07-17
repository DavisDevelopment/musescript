strategy P19 {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.012 && r13 < 40 && (r8 > 28 || r8 > r8[1]): long()
    when r13 > 54 || r8 > 58 || vol > 0.02: flat()
  }
  onPosition {
    when unrealized_pnl < -0.015 * equity: flat()
    when bars_in_trade >= 5 && falling(r13, 3, 3): flat()
    when bars_in_trade >= 8: flat()
  }
}
