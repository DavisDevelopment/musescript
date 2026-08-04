// Minimal class seed WITHOUT FlagshipRisk.
class ProbeSeedBare extends muse.Strat {
  r5 = rsi(close, 5)
  function onBar() {
    when symbol_is("IWM") && bar_index == 1: long()
    when symbol_is("IWM") && bar_index >= 55 && r5 < 45: flat()
  }
}
