template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template TimeCap(n: Window) { onPosition { when bars_in_trade >= n: flat() } }

template HistExit(f: Window, s: Window, g: Window) {
  onPosition { when falling(macd(close, f, s, g).hist, 3, 5): flat() }
}

strategy A06S01_LayeredHistTrendR8 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  m = macd(close, 5, 13, 8)
  Stop(0.05)
  TimeCap(13)
  HistExit(5, 13, 8)
  onBar {
    when (fast > slow || rising(m.hist, 3)) && close > ema(close, 8): long()
    when crossunder(fast, slow) || m.hist < 0: flat()
  }
}
