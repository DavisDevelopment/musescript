// H5 — dual sleeve with faster Donchian (13) for swing-band turnover.

template crownShortExit(fastEma: Window) -> Bool {
  donchHigh(8) || rsiCold(13, 25) || rsiHot(13, 65) || macdBull(8, 21, 5) || aboveEma(fastEma)
}

strategy ProbeFastDual {
  r13 = rsi(close, 13)
  m = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  fast = ema(close, 13)
  gate = sma(close, 21)

  onBar {
    when close > e8 && (close > gate || rising(m.hist, 2)) && donchHigh(13): long()
    when close < e8 && (close < gate || falling(m.hist, 2)) && donchLow(13): short()
    when position() > 0 && (donchLow(8) || rsiHot(13, 75) || belowEma(13) || macdBear(8, 21, 5)): flat()
    when position() < 0 && (donchHigh(8) || rsiCold(13, 25) || aboveEma(13) || macdBull(8, 21, 5)): flat()
  }

  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 8: flat()
    when bars_in_trade >= 5 && unrealized_pnl > 0.025 * equity: flat()
    when bars_in_trade >= 3 && position() > 0 && close < fast: flat()
    when bars_in_trade >= 3 && position() < 0 && close > fast: flat()
    when bars_in_trade >= 3 && position() > 0 && falling(r13, 2): flat()
    when bars_in_trade >= 3 && position() < 0 && rising(r13, 2): flat()
  }
}
