strategy Donchian21x8Exit {

  onBar {

    when high >= highest(high, 21): long()

    when low <= lowest(low, 8): flat()

  }

  onPosition {

    when bars_in_trade >= 13: flat()

  }

}

