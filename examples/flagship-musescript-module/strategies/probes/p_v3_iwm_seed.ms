// Isolated IWM micro-edge: bar-1 seed + late RSI fade.
// PASSes IWM eval_3m alone; ties/loses SPY/QQQ active edge (do not promote).

class ProbeV3IwmSeed extends FlagshipRisk {
  r5 = rsi(close, 5)

  function onBar() {
    when bar_index == 1: long()
    when bar_index >= 55 && r5 < 45: flat()
  }

  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
