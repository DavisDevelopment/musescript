template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template ProfitCap(pct: Scalar, minBars: Window) {
  onPosition { when bars_in_trade >= minBars && unrealized_pnl > pct * equity: flat() }
}

strategy A06S02_CascadeR8 {
  m = macd(close, 5, 13, 8)
  fast = ema(close, 8)
  slow = ema(close, 21)
  Stop(0.06)
  ProfitCap(0.025, 8)
  onBar {
    when rising(m.hist, 3) || fast > slow: long()
    when m.hist < 0 || crossunder(fast, slow): flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
