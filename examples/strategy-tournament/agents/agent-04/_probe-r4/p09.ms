strategy RsiDipOrRecoveryDon {
  onBar {
    r = rsi(close, 13)
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    dip = r < 40 && r > r[1]
    rec = r > 35 && r[1] <= 35
    when e8 > e34 && (dip || rec) && high >= highest(high, 21): long()
    when low <= lowest(low, 13) || r > 68 || e8 < e34: flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
