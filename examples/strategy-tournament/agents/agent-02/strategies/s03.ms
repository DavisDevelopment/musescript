strategy Ema1334Ema55Gate {
  fast = ema(close, 13)
  slow = ema(close, 34)
  trend = ema(close, 55)
  onBar {
    when position() == 0 && crossover(fast, slow) && fast > trend: long()
    when position() != 0 && (crossunder(fast, slow) || close < trend): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
  }
}
