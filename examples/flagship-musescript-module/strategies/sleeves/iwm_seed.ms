// Ceiling sleeve — bar-1 seed + late RSI fade (IWM micro-edge).

strategy IwmSeedSleeve {
  r5 = rsi(close, 5)
  onBar {
    when bar_index == 1: long()
    when bar_index >= 55 && r5 < 45: flat()
  }
}
