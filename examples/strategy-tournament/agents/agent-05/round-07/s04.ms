template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template relativeVolOk(n: Window) -> Bool {
  volume <= 0 || volume > sma(volume, n)
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

strategy S04_VolSqueeze834R7 {
  a8 = atr(close, 8)
  a34 = atr(close, 34)

  TrailingStop(0.05)
  TimeCap(13)

  onBar {
    when a8 < a34 * 0.89 && relativeVolOk(21) && donchianHigh(21): long()
    when donchianLow(13): flat()
  }
}
