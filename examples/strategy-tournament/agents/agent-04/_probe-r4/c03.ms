strategy S03Candidate {
  r = rsi(close, 13)
  e8 = ema(close, 8)
  e34 = ema(close, 34)
  onBar {
    when position() == 0 && e8 > e34 && close > e34 && r < 42: long()
    when position() != 0 && (high >= highest(high, 13) || r > 68 || e8 < e34): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
