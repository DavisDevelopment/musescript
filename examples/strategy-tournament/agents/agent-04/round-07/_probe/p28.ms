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

strategy P28 {
  r13 = rsi(close, 13)
  r8 = rsi(close, 8)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.015 && r13 < 42 && r8 < 45: long()
    when r13 > 55 || r8 > 58 || vol > 0.025: flat()
  }
  EquityHardStop(0.016)
  ProfitLock(5, 0.012)
  onPosition {
    when bars_in_trade >= 5 && falling(r13, 3, 3): flat()
    when bars_in_trade >= 8: flat()
  }
}
