template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A01S05_MicroDonSoftR8 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  spread = fast - slow
  m = macd(close, 5, 13, 8)
  Stop(0.04)
  onBar {
    when (fast > slow && rising(spread, 2)) || (donHigh(8) && m.hist > 0): long()
    when donLow(8) || crossunder(fast, slow) || m.hist < 0: flat()
  }
  onPosition {
    when falling(m.hist, 3, 5): flat()
    when bars_in_trade >= 13: flat()
  }
}
