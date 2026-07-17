template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeEma834Gate21 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  gate = sma(close, 21)

  TrailingStop(0.05)

  onBar {
    when (fast > slow || close > fast) && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }

  onPosition {
    when bars_in_trade >= 13: flat()
  }
}
