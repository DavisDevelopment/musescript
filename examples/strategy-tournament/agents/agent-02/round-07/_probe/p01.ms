template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}

strategy ProbeEma834Or55 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  gate = sma(close, 55)
  spread = fast - slow

  TrailingStop(0.05)

  onBar {
    when emaTrendEntry(8, 34) && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }

  onPosition {
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when falling(spread, 3, 5): flat()
  }
}
