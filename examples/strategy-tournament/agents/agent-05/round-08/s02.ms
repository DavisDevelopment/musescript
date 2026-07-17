template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A05S02_Don5BroadR8 {
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when donHigh(5) || rising(m.hist, 3): long()
    when donLow(5) || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(m.hist, 3, 5): flat()
  }
}
