strategy P22 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r < 41: long()
    when r > 56 || vol > 0.025: flat()
  }
  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.01 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
