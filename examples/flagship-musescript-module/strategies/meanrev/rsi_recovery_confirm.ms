// Mean-reversion #29 — RSI recovery-confirmation entry: rather than buying at
// the exact oversold cross (like #1/#2), this waits for RSI to have dipped
// below 30 within the last 15 bars (bars_since) AND already recovered back
// above 40 — trading the confirmed bounce leg, not the falling knife itself.
// Later, more conservative entry timing than every threshold-cross variant
// above; the two conditions don't overlap (entry needs r>40, the oversold
// check looks at whether that happened in the PAST), so it's not tautological.

strategy RsiRecoveryConfirm {
  r = rsi(close, 14)
  wasOversold = bars_since(r < 30) <= 15
  onBar {
    when r > 40 && wasOversold: long()
    when r > 65: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
