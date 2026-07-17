template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template emaTrailExit(len: Window) -> Bool {
  donchianLow(13) || macdBear(8, 21, 5) || belowEma(len)
}

template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeExit(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}

template TrailBelowEma(len: Window, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && close < ema(close, len): flat()
  }
}

strategy S03_MacdEmaCrownR4 {
  trend = ema(close, 21)

  onBar {
    when donchianHigh(21): long()
    when emaTrailExit(21): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && close < trend: flat()
    when bars_in_trade >= 5 && unrealized_pnl < -0.03 * equity: flat()
  }
}
