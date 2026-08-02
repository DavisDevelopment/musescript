module RiskKit(stopPct: Scalar = 0.05, timeBars: Window = 13) {
  onPosition {
    when unrealized_pnl < -stopPct * equity: flat()
    when bars_in_trade >= timeBars: flat()
  }
}
strategy S {
  use RiskKit(stopPct = 0.05, timeBars = 13)
  onBar { when crossover(sma(close, 8), sma(close, 21)): long() }
}
