template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

template TimeCap(n: Window) { onPosition { when bars_in_trade >= n: flat() } }

strategy A06S03_DualPathR8 {
  m = macd(close, 5, 13, 8)
  s = macd(close, 13, 34, 8)
  Stop(0.06)
  TimeCap(21)
  onBar {
    when (rising(m.hist, 3) && m.hist > 0) || (s.hist > 0 && close > ema(close, 13)): long()
    when (m.hist < 0 && s.hist < 0) || close < ema(close, 8): flat()
  }
  onPosition { when falling(m.hist, 3, 5): flat() }
}
