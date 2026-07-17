strategy ProbeRsiRange {
  r = rsi(close, 21)
  mid = sma(close, 55)
  onBar {
    when position() == 0 && r < 40 && close >= mid: long()
    when r > 55: flat()
  }
  onPosition {
    when unrealized_pnl < -0.03 * equity: flat()
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.02 * equity: flat()
  }
}
