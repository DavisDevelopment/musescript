strategy ProbeRecoveryVol {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r8 > 30 && r8[1] <= 30 && r13 > 35: long()
    when r13 > 55 || r8 > 58 || vol > 0.025: flat()
  }
  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
