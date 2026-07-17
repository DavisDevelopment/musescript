strategy ProbeNoCrypto {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.008 && r < 40: long()
    when r > 54: flat()
  }
  onPosition {
    when unrealized_pnl < -0.012 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
