template lowVolGate(maxVol: Scalar) -> Bool {
  atr(close, 14) / close < maxVol
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

strategy S03_RsiRecoveryVolR7 {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 14) / close

  onBar {
    when position() == 0 && lowVolGate(0.015) && r8 > 30 && r8[1] <= 30 && r13 > 35: long()
    when rsiOverbought(13, 55) || rsiOverbought(8, 58) || vol > 0.025: flat()
  }

  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
