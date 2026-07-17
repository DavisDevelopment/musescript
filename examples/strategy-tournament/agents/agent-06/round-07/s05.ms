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
  macdBear(fFast, fSlow, fSig) && macdBear(sFast, sSlow, sSig)
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

template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeExit(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}

template StagedProfitLock() {
  onPosition {
    when bars_in_trade >= 5 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.05 * equity: flat()
  }
}

template DualRsiScalpExit(fastLen: Window, fastHi: Scalar, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && rsiOverbought(fastLen, fastHi): flat()
  }
}

template AtrChandelierExit(len: Window, mult: Scalar, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && atrChandelier(len, mult): flat()
  }
}

template StagedDonchianExit(tightLen: Window, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && donchianLow(tightLen): flat()
  }
}

template DualMacdConfirm(minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && dualMacdBear(8, 21, 5, 13, 34, 8): flat()
  }
}

template TrailBelowEma(len: Window, minBars: Scalar) {
  onPosition {
    when bars_in_trade >= minBars && close < ema(close, len): flat()
  }
}

strategy S05_MaximalistCrownR7 {
  e8 = ema(close, 8)
  m8 = macd(close, 8, 21, 5)
  m = macd(close, 13, 34, 8)
  anchor = ema(close, 34)

  onBar {
    when close > e8 && donchianHigh(8): long()
    when cascadeExit(13): flat()
  }

  TrailingStop(0.08)
  TimeExit(34)
  StagedProfitLock()
  DualRsiScalpExit(8, 76, 5)
  AtrChandelierExit(8, 2, 5)
  StagedDonchianExit(8, 8)
  DualMacdConfirm(8)
  TrailBelowEma(13, 5)

  onPosition {
    when bars_in_trade >= 8 && close < anchor && m8.hist < 0 && m.hist < 0: flat()
    when falling(m8.hist, 3, 5): flat()
    when falling(m.hist, 2, 8): flat()
  }
}
