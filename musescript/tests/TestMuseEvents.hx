package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.runtime.MuseEvents;
import musescript.runtime.MuseRuntime;

/**
 * MuseEvents bus — subscribe/emit/off, truth quarantine, wildcards, pumpHostEvent.
 */
class TestMuseEvents extends Test {
	public function setup() {
		MuseEvents.clear();
	}

	public function teardown() {
		MuseEvents.clear();
	}

	public function testOnEmitOff() {
		var seen:Array<Dynamic> = [];
		var handler = function(e:Dynamic) seen.push(e);
		MuseEvents.on("order.fill", handler);
		var r = MuseEvents.emit({ type: "order.fill", symbol: "SPY", qty: 1, price: 100.0, side: "long" });
		Assert.isTrue(r.ok == true);
		Assert.equals(1, r.delivered);
		Assert.equals(1, seen.length);
		Assert.equals("SPY", Reflect.field(seen[0], "symbol"));
		Assert.isTrue(Reflect.field(seen[0], "deterministic") == true);
		Assert.isTrue(MuseEvents.off("order.fill", handler));
		MuseEvents.emit({ type: "order.fill", symbol: "QQQ", qty: 1, price: 1.0, side: "long" });
		Assert.equals(1, seen.length);
	}

	public function testOnce() {
		var n = 0;
		MuseEvents.once("lifecycle.start", function(_:Dynamic) n++);
		MuseEvents.emit({ type: "lifecycle.start" });
		MuseEvents.emit({ type: "lifecycle.start" });
		Assert.equals(1, n);
		Assert.equals(0, MuseEvents.listenerCount("lifecycle.start"));
	}

	public function testWildcardFamily() {
		var types:Array<String> = [];
		MuseEvents.on("order.*", function(e:Dynamic) types.push(Reflect.field(e, "type")));
		MuseEvents.emit({ type: "order.submit", side: "long" });
		MuseEvents.emit({ type: "order.fill", side: "long", qty: 1, price: 1.0 });
		MuseEvents.emit({ type: "watchlist.ping", symbol: "X" });
		Assert.equals(2, types.length);
		Assert.equals("order.submit", types[0]);
		Assert.equals("order.fill", types[1]);
	}

	public function testTruthModeBlocksHostUi() {
		MuseEvents.setMode("truth");
		var n = 0;
		MuseEvents.on("ui.click", function(_:Dynamic) n++);
		MuseEvents.on("order.fill", function(_:Dynamic) n++);
		var blocked = MuseEvents.pumpHostEvent({ type: "ui.click", target: "btn" });
		Assert.isFalse(blocked.ok == true);
		Assert.equals(0, n);
		var ok = MuseEvents.emit({ type: "order.fill", side: "long", qty: 1, price: 10.0 });
		Assert.isTrue(ok.ok == true);
		Assert.equals(1, n);
		MuseEvents.setMode("live");
		var live = MuseEvents.pumpHostEvent("ui.click", { target: "btn" });
		Assert.isTrue(live.ok == true);
		Assert.equals(2, n);
	}

	public function testPumpHostEventStampsSource() {
		var got:Dynamic = null;
		MuseEvents.on("watchlist.ping", function(e:Dynamic) got = e);
		MuseEvents.pumpHostEvent("watchlist.ping", { symbol: "AAPL", kind: "alert" });
		Assert.notNull(got);
		Assert.equals("host", Reflect.field(got, "source"));
		Assert.equals("watchlist", Reflect.field(got, "family"));
		Assert.isFalse(Reflect.field(got, "deterministic") == true);
	}

	public function testCatalogHasFamilies() {
		var cat = MuseEvents.catalog();
		Assert.equals(MuseEvents.SCHEMA, Reflect.field(cat, "schemaVersion"));
		var events:Array<Dynamic> = Reflect.field(cat, "events");
		Assert.isTrue(events.length >= 20);
		var types = [for (e in events) Reflect.field(e, "type")];
		Assert.isTrue(types.indexOf("order.fill") >= 0);
		Assert.isTrue(types.indexOf("world.shock") >= 0);
		Assert.isTrue(types.indexOf("lifecycle.dispose") >= 0);
	}

	public function testRuntimeFacades() {
		var n = 0;
		var h = function(_:Dynamic) n++;
		MuseRuntime.on("meta.diagnostics", h);
		MuseRuntime.pumpHostEvent({ type: "meta.diagnostics", diagnostics: [] });
		Assert.equals(1, n);
		MuseRuntime.off("meta.diagnostics", h);
		var cat = MuseRuntime.eventsCatalog();
		Assert.equals(MuseEvents.SCHEMA, Reflect.field(cat, "schemaVersion"));
		Assert.equals("live", MuseRuntime.eventsGetMode());
	}

	public function testListenerErrorIsolated() {
		var n = 0;
		MuseEvents.on("order.cancel", function(_:Dynamic) throw "boom");
		MuseEvents.on("order.cancel", function(_:Dynamic) n++);
		var r = MuseEvents.emit({ type: "order.cancel", orderId: "1" });
		Assert.isTrue(r.ok == true);
		Assert.equals(2, r.delivered);
		Assert.equals(1, n);
	}

	public function testCheckEmitsDiagnostics() {
		var got:Dynamic = null;
		MuseEvents.on("meta.diagnostics", function(e:Dynamic) got = e);
		var r = MuseRuntime.check('@strategy("x") @on(bar) { var a = 1; }');
		Assert.isTrue(r.ok == true);
		Assert.notNull(got);
		Assert.equals("meta.diagnostics", Reflect.field(got, "type"));
	}

	/** Truth mode must not allow UI events to poison a det path. */
	public function testDeterminismPolicyUnknownIsHost() {
		Assert.isFalse(MuseEvents.isDeterministic("ui.hack"));
		Assert.isFalse(MuseEvents.isDeterministic("nope.nope"));
		Assert.isTrue(MuseEvents.isDeterministic("lifecycle.start"));
		MuseEvents.setMode("truth");
		Assert.isFalse(MuseEvents.isAllowed("order.status"));
		Assert.isTrue(MuseEvents.isAllowed("market.bar"));
	}
}
