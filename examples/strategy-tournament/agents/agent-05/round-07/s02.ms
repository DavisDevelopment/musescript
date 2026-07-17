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

strategy S02_AtrSqueezeDon21R7 {
  a13 = atr(close, 13)
  a55 = atr(close, 55)

  TrailingStop(0.05)
  TimeCap(13)

  onBar {
    when a13 < a55 * 0.85 && donchianHigh(21): long()
    when donchianLow(13): flat()
  }
}
