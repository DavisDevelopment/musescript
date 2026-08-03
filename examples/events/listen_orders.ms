// Listen to order-family events (bus + language stream sketch).
//
// Host (Lab / museRuntimeClient):
//   MuseRuntime.on("order.*", (e) => console.log(e.type, e.status || e.side));
//   MuseRuntime.pumpHostEvent({ type: "order.status", symbol: "SPY", status: "filled" });
//   MuseRuntime.pumpHostEvent({ type: "order.suggested", summary: { n: 1 }, runId: "r1" });
//
// Swarm live path pumps `order.suggested` from createLiveScheduler.
// Broker submit/fill/reject/status: mobile orderMuseEvents.js ← TradeSheet + DeployBookSheet.
//
// Docs: docs/MUSE_EVENTS.md

{
  @strategy("ListenOrders")
  // Language twin: when Lab bridges the bus → MuseInterp.dispatchEvents("orders", …)
  @on(orders) {
    log("order_event");
  }
  @on(bar) {
    // Trading stays on @on(bar); bus listeners never become a P&L ranking channel.
    plot(close, "close");
  }
}
