template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeRsiDonShort {
  r = rsi(close, 13)
  onBar {
    when position() == 0 && r < 38 && close > sma(close, 89): long()
    when r > 55 || low <= lowest(low, 8): flat()
  }
  TrailingStop(0.04)
  onPosition {
    when bars_in_trade >= 8: flat()
  }
}
