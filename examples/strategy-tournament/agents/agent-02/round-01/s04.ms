strategy Ema813Ex21Ema55 {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)
  trend = ema(close, 55)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend: long()
    when position() != 0 && (crossunder(fast, exitMa) || close < trend): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
  }
}
