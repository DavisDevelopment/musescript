template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

strategy ProbeEma834Bare {
  fast = ema(close, 8)
  slow = ema(close, 34)
  spread = fast - slow

  TrailingStop(0.05)

  onBar {
    when fast > slow || close > fast: long()
    when crossunder(fast, slow): flat()
  }

  onPosition {
    when bars_in_trade >= 21: flat()
    when falling(spread, 3, 5): flat()
  }
}
