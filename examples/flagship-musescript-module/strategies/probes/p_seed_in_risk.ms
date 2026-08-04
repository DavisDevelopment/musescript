// Minimal class seed matching iwm_seed DNA inside FlagshipRisk (isolates risk inheritance).
class ProbeSeedRisk extends FlagshipRisk {
  r5 = rsi(close, 5)
  function onBar() {
    when symbol_is("IWM") && bar_index == 1: long()
    when symbol_is("IWM") && bar_index >= 55 && r5 < 45: flat()
  }
  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
