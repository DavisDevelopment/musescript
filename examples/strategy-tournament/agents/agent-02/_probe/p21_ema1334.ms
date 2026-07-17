strategy Ema1334DonchHard {
  onBar {
    e13 = ema(close, 13)
    e34 = ema(close, 34)
    when e13 > e34 && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
