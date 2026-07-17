template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A05S01_Don8HistR8 {
  m = macd(close, 5, 13, 8)
  Stop(0.06)
  onBar {
    when donHigh(8) && m.hist > -0.001: long()
    when donLow(8) || m.hist < 0: flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
