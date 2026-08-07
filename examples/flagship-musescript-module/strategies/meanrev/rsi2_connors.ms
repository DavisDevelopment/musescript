// Mean-reversion #1 — Connors RSI(2): the shortest-horizon oversold bounce.
// Classic Larry Connors setup: an RSI so short it's essentially a 2-bar overbought/
// oversold gauge. Entry only in an uptrend context (price above SMA200 proxy via a
// longer SMA here, since these tapes are short) so we're buying dips, not knives.

strategy Rsi2Connors {
  r2 = rsi(close, 2)
  trendUp = sma(close, 5) > sma(close, 20)
  onBar {
    when r2 < 10 && trendUp: long()
    when r2 > 70: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 6: flat()
  }
}
