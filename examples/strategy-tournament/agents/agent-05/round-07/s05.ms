template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeCap(n: Window) {
  onPosition {
    when bars_in_trade >= n: flat()
  }
}

template AtrFallExit(fast: Window, slope: Window, minBars: Window) {
  onPosition {
    when falling(atr(close, fast), slope, minBars): flat()
  }
}

strategy S05_Squeeze834FallFlagshipR7 {
  a8 = atr(close, 8)
  a34 = atr(close, 34)

  TrailingStop(0.05)
  TimeCap(13)
  AtrFallExit(8, 3, 8)

  onBar {
    when a8 < a34 * 0.89 && donchianHigh(21): long()
    when donchianLow(13): flat()
  }

  onPosition {
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
  }
}
