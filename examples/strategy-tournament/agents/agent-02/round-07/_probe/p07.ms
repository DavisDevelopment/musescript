template TrailingStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}

template trendGateOr(short: Window, long: Window) -> Bool {
  close > sma(close, short) || close > ema(close, long)
}

strategy ProbeEma834OrGate {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trail = ema(close, 13)
  spread = fast - slow

  TrailingStop(0.04)

  onBar {
    when position() == 0 && emaTrendEntry(8, 34) && trendGateOr(21, 55): long()
    when crossunder(fast, slow) || close < sma(close, 21): flat()
  }

  onPosition {
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.021 * equity: flat()
    when bars_in_trade >= 5 && close < trail: flat()
    when falling(spread, 5, 8): flat()
  }
}
