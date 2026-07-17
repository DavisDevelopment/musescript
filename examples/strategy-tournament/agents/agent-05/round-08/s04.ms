template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A05S04_Don13OrHistR8 {
  m = macd(close, 5, 13, 8)
  Stop(0.07)
  onBar {
    when donHigh(13) || (donHigh(5) && m.hist > 0): long()
    when donLow(8) || m.hist < 0: flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
