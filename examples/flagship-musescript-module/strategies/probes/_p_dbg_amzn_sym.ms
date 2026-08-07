// minimal symbol_is probe
class TestAmznSym extends muse.Strat {
  function onBar() {
    when symbol_is("AMZN") && bar_index == 1: long()
    when (!symbol_is("AMZN")) && bar_index == 1: long()
    when bars_in_trade >= 3: flat()
  }
}
