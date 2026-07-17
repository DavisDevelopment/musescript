strategy Donchian34x13Wide {
  onBar {
    when high >= highest(high, 34): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
