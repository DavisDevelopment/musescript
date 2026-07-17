template Stop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}

strategy A04S03_RsiTrendPullbackR8 {
  r = rsi(close, 13)
  fast = ema(close, 8)
  slow = ema(close, 34)
  Stop(0.05)
  onBar {
    when r < 55 && fast > slow: long()
    when r > 68 || crossunder(fast, slow): flat()
  }
  onPosition { when bars_in_trade >= 13: flat() }
}
