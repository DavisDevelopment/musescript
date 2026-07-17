strategy Squeeze513Donchian13 {

  atrFast = atr(close, 5)

  atrSlow = atr(close, 13)

  onBar {

    when atrFast < atrSlow * 0.98 && high >= highest(high, 13): long()

    when low <= lowest(low, 5): flat()

  }

  onPosition {

    when unrealized_pnl < -0.05 * equity: flat()

  }

}

