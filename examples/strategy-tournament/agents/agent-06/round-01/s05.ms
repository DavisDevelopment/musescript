template fastEmaCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template slowEmaExit(fast: Window, exitLen: Window) -> Bool {
  crossunder(ema(close, fast), ema(close, exitLen))
}

template macdBull(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist > 0
}

template aboveTrend(len: Window) -> Bool {
  close > sma(close, len)
}

template donchianBreak(len: Window) -> Bool {
  close >= highest(high, len)
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

strategy S05_CascadeMaestro {
  fast = ema(close, 8)
  slow = ema(close, 34)
  exitMa = ema(close, 21)
  anchor = sma(close, 55)
  m = macd(close, 13, 34, 8)

  onBar {
    when fastEmaCross(8, 34) && aboveTrend(55) && (macdBull(13, 34, 8) || donchianBreak(21)): long()
    when slowEmaExit(8, 21) || close < anchor: flat()
    when m.hist < 0 && position() != 0: flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 55: flat()
    when bars_in_trade >= 21 && close < exitMa: flat()
  }
}
