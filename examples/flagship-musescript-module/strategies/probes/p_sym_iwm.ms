strategy SymProbe {
  onBar {
    when symbol_is("IWM") && bar_index == 1: long()
    when symbol_is("IWM") && bar_index >= 40: flat()
    when (!symbol_is("IWM")) && bar_index == 2: long()
  }
}
