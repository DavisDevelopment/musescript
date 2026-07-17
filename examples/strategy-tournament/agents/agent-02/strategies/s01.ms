strategy Ema821Sma55Gate {
  fast = ema(close, 8)
  slow = ema(close, 21)
  trend = sma(close, 55)
  onBar {
    when position() == 0 && crossover(fast, slow) && close > trend: long()
    when position() != 0 && (crossunder(fast, slow) || close < trend): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
  }
}
