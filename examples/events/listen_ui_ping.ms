// UI / user-interaction ping (host-injected, non-deterministic).
//
// Host:
//   MuseRuntime.eventsSetMode("live"); // never on truth/evolve paths
//   MuseRuntime.on("ui.command", (e) => { /* palette */ });
//   MuseRuntime.pumpHostEvent({ type: "ui.click", target: "chart", id: "buy" });
//   MuseRuntime.pumpHostEvent({ type: "ui.selection", kind: "symbol", symbol: "SPY" });
//
// Status today: Lab focus/selection, Studio run, Charts widget palette
// (mobile uiMuseEvents.js). Quarantine: truth mode rejects ui.* — see docs/MUSE_EVENTS.md.

{
  @strategy("ListenUiPing")
  @on(ui) {
    log("ui_event");
  }
  @on(bar) {
    plot(close, "close");
  }
}
