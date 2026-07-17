strategy P21 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.014 && r < 41 && close > sma(close, 55): long()
    when r > 55 || vol > 0.024: flat()
  }
  onPosition {
    when unrealized_pnl < -0.02 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.008 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
