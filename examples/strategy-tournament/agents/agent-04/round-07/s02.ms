template lowVolGate(maxVol: Scalar) -> Bool {
  atr(close, 14) / close < maxVol
}

template rsiOversold(len: Window, lo: Scalar) -> Bool {
  rsi(close, len) < lo
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template dualRsiExit() -> Bool {
  rsiOverbought(13, 55) || rsiOverbought(8, 58)
}

strategy S02_RsiDualVolCascadeR7 {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 14) / close

  onBar {
    when position() == 0 && lowVolGate(0.015) && r13 < 42 && r8 < 45: long()
    when dualRsiExit() || vol > 0.025: flat()
  }

  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
