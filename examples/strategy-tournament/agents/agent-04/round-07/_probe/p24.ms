strategy P24 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r < 42 && r > r[1]: long()
    when r > 55 || vol > 0.025: flat()
  }
  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
