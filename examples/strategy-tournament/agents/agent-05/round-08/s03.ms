template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A05S03_AtrSqueezeSoftR8 {
  a8 = atr(close, 8)
  a34 = atr(close, 34)
  m = macd(close, 5, 13, 8)
  Stop(0.06)
  onBar {
    when (a8 < a34 * 1.00 && donHigh(8)) || rising(m.hist, 3): long()
    when donLow(8) || falling(a8, 3, 5) || m.hist < 0: flat()
  }
}
