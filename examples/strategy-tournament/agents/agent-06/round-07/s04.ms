template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template atrChandelier(len: Window, mult: Scalar) -> Bool {
  close < highest(high, len) - mult * atr(close, len)
}

template cascadeExit(fastEma: Window) -> Bool {
  donchianLow(13) || macdBear(13, 34, 8) || rsiOverbought(13, 72) || belowEma(fastEma)
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

template ProfitLock(minBars: Scalar, pct: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && unrealized_pnl > pct * equity: flat()
  }
}

template AtrChandelierExit(len: Window, mult: Scalar, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && atrChandelier(len, mult): flat()
  }
}

template TrailBelowEma(len: Window, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && close < ema(close, len): flat()
  }
}

strategy S04_AtrChandelierR7 {
  e8 = ema(close, 8)
  m8 = macd(close, 8, 21, 5)
  anchor = ema(close, 34)

  onBar {
    when close > e8 && donchianHigh(8): long()
    when cascadeExit(13): flat()
  }

  EquityHardStop(0.08)
  TimeExit(21)
  ProfitLock(5, 0.03)
  AtrChandelierExit(8, 2, 5)
  TrailBelowEma(13, 5)

  onPosition {
    when bars_in_trade >= 8 && close < anchor && m8.hist < 0: flat()
    when falling(m8.hist, 3, 5): flat()
  }
}
