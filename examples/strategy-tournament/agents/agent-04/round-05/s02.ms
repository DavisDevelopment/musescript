template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template rsiMomentumFail(len: Window, lo: Scalar) -> Bool {
  rsi(close, len) < lo
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template rsiCascadeExit(fastEma: Window) -> Bool {
  donchianLow(13) || rsiOverbought(13, 72) || belowEma(fastEma)
}

strategy S02_RsiCascadeTrailR5 {
  fast = ema(close, 13)

  onBar {
    when donchianHigh(21): long()
    when rsiCascadeExit(13): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
  }
}
