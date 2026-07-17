template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}

strategy S04_Ema821Gate21R7 {
  fast = ema(close, 8)
  slow = ema(close, 21)
  gate = sma(close, 21)
  spread = fast - slow

  TrailingStop(0.05)

  onBar {
    when emaTrendEntry(8, 21) && close > gate: long()
    when crossunder(fast, slow) || close < gate: flat()
  }

  onPosition {
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.013 * equity: flat()
    when falling(spread, 3, 5): flat()
  }
}
