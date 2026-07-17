strategy Donchian21x13TimeR2 {

  onBar {

    when high >= highest(high, 21): long()

    when low <= lowest(low, 13): flat()

  }

  onPosition {

    when bars_in_trade >= 13: flat()

    when bars_in_trade >= 8 && low <= lowest(low, 8): flat()

    when unrealized_pnl < -0.05 * equity: flat()

  }

}

