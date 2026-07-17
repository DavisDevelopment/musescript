template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeEma834Crown {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trail = ema(close, 13)
  gate = sma(close, 21)
  spread = fast - slow

  TrailingStop(0.04)

  onBar {
    when (fast > slow || close > fast) && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }

  onPosition {
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when bars_in_trade >= 5 && close < trail: flat()
    when bars_in_trade >= 8 && falling(spread, 5, 8): flat()
  }
}
