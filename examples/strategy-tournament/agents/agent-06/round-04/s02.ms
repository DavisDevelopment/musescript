template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template macdBull(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist > 0
}

template exitRegimeFlip() -> Bool {
  donchianLow(13) || macdBear(8, 21, 5)
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

strategy S02_MacdExitVaultR4 {
  m = macd(close, 8, 21, 5)

  onBar {
    when donchianHigh(21): long()
    when exitRegimeFlip(): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && m.hist < 0: flat()
  }
}
