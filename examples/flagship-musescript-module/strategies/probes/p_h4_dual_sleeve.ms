// H4 — long Donchian crown + mirrored short sleeve for bear tapes.

template crownShortExit(fastEma: Window) -> Bool {
  donchHigh(13) || rsiCold(13, 25) || rsiCold(8, 22) || rsiHot(13, 65) || macdBull(13, 34, 8) || aboveEma(fastEma)
}

strategy ProbeDualSleeve {
  r13 = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  fast = ema(close, 13)
  anchor = ema(close, 34)
  gate = sma(close, 34)

  onBar {
    // Long breakout in bullish structure
    when close > e8 && close > gate && donchHigh(21): long()
    // Short breakdown in bearish structure
    when close < e8 && close < gate && donchLow(21): short()
    // Long exits
    when position() > 0 && crownExit(13): flat()
    // Short exits
    when position() < 0 && crownShortExit(13): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && position() > 0 && close < fast: flat()
    when bars_in_trade >= 5 && position() < 0 && close > fast: flat()
    when bars_in_trade >= 8 && position() > 0 && close < anchor && m.hist < 0: flat()
    when bars_in_trade >= 8 && position() < 0 && close > anchor && m.hist > 0: flat()
    when bars_in_trade >= 5 && position() > 0 && falling(r13, 3): flat()
    when bars_in_trade >= 5 && position() < 0 && rising(r13, 3): flat()
  }
}
