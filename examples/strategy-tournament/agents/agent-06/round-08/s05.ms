template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template TimeCap(n: Window) { onPosition { when bars_in_trade >= n: flat() } }

template ProfitCap(pct: Scalar, minBars: Window) {
  onPosition { when bars_in_trade >= minBars && unrealized_pnl > pct * equity: flat() }
}

strategy A06S05_MaxCompositeR8 {
  m = macd(close, 5, 13, 8)
  fast = ema(close, 8)
  slow = ema(close, 34)
  r = rsi(close, 13)
  Stop(0.05)
  TimeCap(13)
  ProfitCap(0.021, 8)
  onBar {
    when (rising(m.hist, 3) && r < 70) || (fast > slow && close > fast): long()
    when m.hist < 0 || r > 75 || crossunder(fast, slow): flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
