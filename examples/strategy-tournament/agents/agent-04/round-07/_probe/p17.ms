strategy P17 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.013 && r < 40: long()
    when r > 53 || vol > 0.022: flat()
  }
  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
