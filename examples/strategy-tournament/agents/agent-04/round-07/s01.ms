template lowVolGate(maxVol: Scalar) -> Bool {
  atr(close, 14) / close < maxVol
}

template rsiOversold(len: Window, lo: Scalar) -> Bool {
  rsi(close, len) < lo
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

strategy S01_RsiVolGateDipR7 {
  r = rsi(close, 13)
  vol = atr(close, 14) / close

  onBar {
    when position() == 0 && lowVolGate(0.015) && rsiOversold(13, 42): long()
    when rsiOverbought(13, 55) || vol > 0.025: flat()
  }

  onPosition {
    when unrealized_pnl < -0.018 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
