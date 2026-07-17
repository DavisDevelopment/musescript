template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template donHigh(n: Window) -> Bool { high >= highest(high, n) }

template donLow(n: Window) -> Bool { low <= lowest(low, n) }

strategy A06S04_BreakTrendTemplateR8 {
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  onBar {
    when (donHigh(8) && m.hist > -0.001) || rising(m.hist, 3): long()
    when donLow(8) || m.hist < 0: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when falling(m.hist, 3, 5): flat()
  }
}
