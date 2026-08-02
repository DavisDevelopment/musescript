// Shared expr templates — stitched ahead of the strategy by the harness.
// Fib windows mirror tournament winners that survived equity + crypto/FX stress.

template donchHigh(len: Window) -> Bool {
  high >= highest(high, len)
}

template donchLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template aboveEma(len: Window) -> Bool {
  close > ema(close, len)
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template macdBull(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist > 0
}

template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {
  macd(close, fast, slow, sig).hist < 0
}

template rsiHot(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template rsiCold(len: Window, lo: Scalar) -> Bool {
  rsi(close, len) < lo
}

template trendAligned(fast: Window, slow: Window, gate: Window) -> Bool {
  ema(close, fast) > ema(close, slow) && close > sma(close, gate)
}

// Classic tournament crown (RSI fail included) — aggressive flat.
template crownExit(fastEma: Window) -> Bool {
  donchLow(13) || rsiHot(13, 75) || rsiHot(8, 78) || rsiCold(13, 35) || rsiCold(8, 32) || macdBear(13, 34, 8) || belowEma(fastEma)
}

// Softer crown — higher RSI TP, no RSI-cold onBar (v1e evidence: lifts SPY/QQQ/NVDA/AMD).
template softCrownExit(fastEma: Window) -> Bool {
  donchLow(13) || rsiHot(13, 80) || rsiHot(8, 82) || macdBear(13, 34, 8) || belowEma(fastEma)
}

// ATR sleeve exit — NO macdBear (that pair murdered AAPL crown∪ATR unions).
template atrSleeveExit(fastEma: Window) -> Bool {
  belowEma(fastEma) || rsiHot(13, 80) || rsiHot(8, 82) || donchLow(8)
}

// Soft crown minus macdBear — ATR trades keep structure without MACD whipsaw.
template softCrownNoMacd(fastEma: Window) -> Bool {
  donchLow(13) || rsiHot(13, 80) || rsiHot(8, 82) || belowEma(fastEma)
}

// Sticky / seed sleeve — only structural failure or late fade (IWM DNA).
template stickySleeveExit(r5: Scalar) -> Bool {
  donchLow(34) || (bars_in_trade >= 40 && r5 < 45)
}

// Bounce / MACD-zero sleeve — short leash.
template bounceSleeveExit() -> Bool {
  macd(close, 8, 21, 5).hist < 0 || bars_in_trade >= 13 || rsiHot(13, 78)
}
