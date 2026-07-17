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

strategy P20 {
  r = rsi(close, 21)
  vol = atr(close, 14) / close
  onBar {
    when position() == 0 && vol < 0.012 && r < 42: long()
    when r > 54 || vol > 0.021: flat()
  }
  EquityHardStop(0.015)
  ProfitLock(5, 0.012)
  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
