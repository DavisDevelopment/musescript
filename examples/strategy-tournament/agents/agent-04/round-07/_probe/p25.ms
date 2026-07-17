template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy P25 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r < 42: long()
    when r > 55 || vol > 0.025: flat()
  }
  EquityHardStop(0.018)
  onPosition {
    when bars_in_trade >= 5 && unrealized_pnl > 0.012 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
