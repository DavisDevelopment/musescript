template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template ProfitLock(minBars: Window, pct: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && unrealized_pnl > pct * equity: flat()
  }
}

template lowVolGate(maxVol: Scalar) -> Bool {
  atr(close, 14) / close < maxVol
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template dualRsiExit() -> Bool {
  rsiOverbought(13, 55) || rsiOverbought(8, 58)
}

strategy S05_RsiFxFlagshipR7 {
  r8 = rsi(close, 8)
  r13 = rsi(close, 13)
  vol = atr(close, 14) / close

  onBar {
    when position() == 0 && lowVolGate(0.015) && r13 < 42 && r8 < 45: long()
    when dualRsiExit() || vol > 0.025: flat()
  }

  EquityHardStop(0.016)
  ProfitLock(5, 0.012)

  onPosition {
    when bars_in_trade >= 5 && falling(r13, 3, 3): flat()
    when bars_in_trade >= 5 && falling(r8, 2, 3) && r8 < 50: flat()
    when bars_in_trade >= 13: flat()
  }
}
