template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}

strategy S03_Ema1334RisingBurstR7 {
  fast = ema(close, 13)
  slow = ema(close, 34)
  gate = ema(close, 55)
  spread = fast - slow

  TrailingStop(0.04)

  onBar {
    when emaTrendEntry(13, 34) && close > gate && rising(spread, 3): long()
    when crossunder(fast, slow) || close < gate: flat()
  }

  onPosition {
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when falling(spread, 3, 8): flat()
  }
}
