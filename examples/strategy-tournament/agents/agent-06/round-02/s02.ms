template fastEmaCross(fast: Window, slow: Window) -> Bool {
  crossover(ema(close, fast), ema(close, slow))
}

template slowEmaExit(fast: Window, exitLen: Window) -> Bool {
  crossunder(ema(close, fast), ema(close, exitLen))
}

template aboveEmaTrend(len: Window) -> Bool {
  close > ema(close, len)
}

template EquityHardStop(pct: Scalar) {
  onPosition {
    when unrealized_pnl < -pct * equity: flat()
  }
}

template TimeExit(bars: Scalar) {
  onPosition {
    when bars_in_trade >= bars: flat()
  }
}

template TrailBelowEma(len: Window) {
  onPosition {
    when bars_in_trade >= 13 && close < ema(close, len): flat()
  }
}

strategy S02_GateMaestro {
  fast = ema(close, 8)
  slow = ema(close, 34)
  trend = ema(close, 21)
  exitMa = ema(close, 21)

  onBar {
    when position() == 0 && fastEmaCross(8, 34) && aboveEmaTrend(21): long()
    when position() != 0 && (slowEmaExit(8, 21) || close < trend): flat()
  }

  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 13 && close < exitMa: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.04 * equity: flat()
  }
}
