strategy P18 {
  r13 = rsi(close, 13)
  vol = atr(close, 8) / close
  onBar {
    when position() == 0 && vol < 0.011 && r13 < 38: long()
    when r13 > 52 || vol > 0.018: flat()
  }
  onPosition {
    when unrealized_pnl < -0.015 * equity: flat()
    when bars_in_trade >= 5 && falling(r13, 2, 3): flat()
    when bars_in_trade >= 8: flat()
  }
}
