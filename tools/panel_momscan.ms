// PanelRunner smoke strategy (see tools/panel_smoke.ps1).
// Adapted from the CURSOR_PANEL_ORGAN.md reference / TestPortfolioPanel:
// dict() -> dict_new() and rankPick(s, 1, false) -> scan_top(s, 1), the
// names actually registered by DictBuiltins / PortfolioBuiltins.
strategy MomScan {
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, 20))
    }
    // long the top-1 by 20d momentum
    for (sym in scan_top(scores, 1)) {
      when pos(sym) == 0: buy(sym, 1)
    }
  }
}
