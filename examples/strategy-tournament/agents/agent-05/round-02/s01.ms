strategy Donchian21x13Time {

  onBar {

    when high >= highest(high, 21): long()

    when low <= lowest(low, 13): flat()

  }

  onPosition {

    when bars_in_trade >= 13: flat()

  }

}

