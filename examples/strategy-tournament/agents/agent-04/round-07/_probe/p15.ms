strategy ProbeRsiMidBand {
  r = rsi(close, 13)
  band = sma(close, 21)
  onBar {
    when position() == 0 && close < band && r < 45 && r > r[1]: long()
    when r > 55 || close > band * 1.01: flat()
  }
  onPosition {
    when unrealized_pnl < -0.02 * equity: flat()
    when bars_in_trade >= 8: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.01 * equity: flat()
  }
}
