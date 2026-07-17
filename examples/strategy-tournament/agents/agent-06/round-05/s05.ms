template donchianHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template macdFalling(fast: Window, slow: Window, sig: Window, bars: Window) -> Bool {
  falling(macd(close, fast, slow, sig).hist, bars)
}

template dualMacdBear(fFast: Window, fSlow: Window, fSig: Window, sFast: Window, sSlow: Window, sSig: Window) -> Bool {
  macd(close, fFast, fSlow, fSig).hist < 0 && macd(close, sFast, sSlow, sSig).hist < 0
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

template ema8CascadeExit() -> Bool {
  donchianLow(13) || macdBear(13, 34, 8) || rsiOverbought(13, 72) || belowEma(8)
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

template StagedProfitLock() {
  onPosition {
    when bars_in_trade >= 5 && unrealized_pnl > 0.02 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
  }
}

template TrailBelowEma(len: Window, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && close < ema(close, len): flat()
  }
}

template AtrChandelierExit(len: Window, mult: Scalar, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && atrChandelier(len, mult): flat()
  }
}

strategy S05_CascadeCrownR5 {
  slow = macd(close, 13, 34, 8)
  fmacd = macd(close, 8, 21, 5)
  fast = ema(close, 8)
  anchor = ema(close, 21)

  onBar {
    when donchianHigh(21): long()
    when ema8CascadeExit(): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.02 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < fast: flat()
    when bars_in_trade >= 5 && macdFalling(13, 34, 8, 2) && slow.hist < 0: flat()
    when bars_in_trade >= 5 && close < highest(high, 8) - 2 * atr(close, 8): flat()
    when bars_in_trade >= 8 && close < anchor && fmacd.hist < 0 && slow.hist < 0: flat()
  }
}
