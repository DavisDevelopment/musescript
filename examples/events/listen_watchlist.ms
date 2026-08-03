// Watchlist / global ping listeners.
//
// Host:
//   MuseRuntime.on("watchlist.*", (e) => { /* toast / panel */ });
//   MuseRuntime.pumpHostEvent("watchlist.add", { symbol: "AAPL" });
//   MuseRuntime.pumpHostEvent("watchlist.ping", { symbol: "AAPL", kind: "alert", message: "gap" });
//
// Status today: pump API ready; watchlist UI not yet wired (stub).

{
  @strategy("ListenWatchlist")
  @on(watchlist) {
    log("watchlist_event");
  }
  @on(bar) {
    plot(close, "close");
  }
}
