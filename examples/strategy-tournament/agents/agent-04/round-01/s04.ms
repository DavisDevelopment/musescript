strategy Rsi13EmaStack {
  r = rsi(close, 13)
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    when position() == 0 && close > slow && fast > slow && r < 45: long()
    when position() != 0 && (r > 60 || fast < slow): flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
  }
}
