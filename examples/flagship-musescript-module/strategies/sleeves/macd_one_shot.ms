// Ceiling sleeve — classic MACD hist zero-cross (MSFT micro-edge).

strategy MacdOneShotSleeve {
  mz = macd(close, 12, 26, 9)
  gate = sma(close, 34)
  onBar {
    when position() == 0 && crossover(mz.hist, 0) && close > gate: long()
    when mz.hist < 0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
