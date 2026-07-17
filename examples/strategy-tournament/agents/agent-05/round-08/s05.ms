template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A05S05_BreakoutParticipationR8 {
  a8 = atr(close, 8)
  a21 = atr(close, 21)
  m = macd(close, 8, 21, 5)
  Stop(0.05)
  onBar {
    when (donHigh(5) && a8 < a21 * 1.13) || rising(m.hist, 3): long()
    when donLow(5) || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(m.hist, 3, 5): flat()
  }
}
