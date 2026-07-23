package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.OrderBook;
import musescript.harness.OrderSim;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.compile.MuseCompiler;
import musescript.builtins.TradeBuiltins;

/**
 * ROADMAP "Execution realism" first slice: pending-order book semantics.
 * The conservative fill rules under test are documented on OrderBook.hx.
 */
class TestOrderBook extends Test {
	static function bar(i:Int, o:Float, h:Float, l:Float, c:Float):Bar {
		return { open: o, high: h, low: l, close: c, volume: 100.0, time: (i : Float), index: i };
	}

	// ── OrderBook.evalBar unit rules ─────────────────────────────────────────

	public function testLimitBuyFillsAtPxNotBetter() {
		var b = new OrderBook();
		b.place("long", { type: "limit", px: 95.0, qty: 1.0 }, 0);
		// bar 1: opens above px, dips to touch 94 — fills AT px, not at the low
		var fills = b.evalBar(100.0, 101.0, 94.0, 1, 0);
		Assert.equals(1, fills.length);
		Assert.floatEquals(95.0, fills[0].price);
		Assert.equals(0, b.pendingCount());
	}

	public function testLimitBuyGapOpenFillsAtOpen() {
		var b = new OrderBook();
		b.place("long", { type: "limit", px: 95.0 }, 0);
		// gap down through the limit: fill at the (better) open
		var fills = b.evalBar(90.0, 96.0, 89.0, 1, 0);
		Assert.equals(1, fills.length);
		Assert.floatEquals(90.0, fills[0].price);
	}

	public function testLimitBuyNoTouchNoFill() {
		var b = new OrderBook();
		b.place("long", { type: "limit", px: 95.0 }, 0);
		var fills = b.evalBar(100.0, 102.0, 96.0, 1, 0);
		Assert.equals(0, fills.length);
		Assert.equals(1, b.pendingCount()); // still working
	}

	public function testStopBuyBreakoutAndGapThrough() {
		var b = new OrderBook();
		b.place("long", { type: "stop", px: 105.0 }, 0);
		// intrabar breakout: fills at the stop px
		var fills = b.evalBar(100.0, 106.0, 99.0, 1, 0);
		Assert.floatEquals(105.0, fills[0].price);
		// gap-through: fills at the WORSE open, not the stop px
		b.place("long", { type: "stop", px: 105.0 }, 1);
		var fills2 = b.evalBar(110.0, 112.0, 108.0, 2, 0);
		Assert.floatEquals(110.0, fills2[0].price);
	}

	public function testStopSellAsStopLossViaFlat() {
		var b = new OrderBook();
		b.place("flat", { type: "stop", px: 90.0 }, 0);
		// long position: flat sells; breakdown through 90 fills at px
		var fills = b.evalBar(95.0, 96.0, 88.0, 1, 10);
		Assert.equals(1, fills.length);
		Assert.floatEquals(90.0, fills[0].price);
		// with NO position, a flat order is dropped, not kept forever
		b.place("flat", { type: "stop", px: 90.0 }, 1);
		Assert.equals(0, b.evalBar(95.0, 96.0, 88.0, 2, 0).length);
		Assert.equals(0, b.pendingCount());
	}

	public function testNoSameBarFill() {
		var b = new OrderBook();
		b.place("long", { type: "market" }, 5);
		// same bar: not eligible (placed during this bar's handlers)
		Assert.equals(0, b.evalBar(100.0, 101.0, 99.0, 5, 0).length);
		Assert.equals(1, b.pendingCount());
		// next bar: market fills at open
		var fills = b.evalBar(102.0, 103.0, 101.0, 6, 0);
		Assert.floatEquals(102.0, fills[0].price);
	}

	public function testTifExpiry() {
		var b = new OrderBook();
		b.place("long", { type: "limit", px: 90.0, tifBars: 1 }, 0);
		// bar 1 (its only eligible bar): no touch → stays for this bar only
		Assert.equals(0, b.evalBar(100.0, 101.0, 99.0, 1, 0).length);
		Assert.equals(1, b.pendingCount());
		// bar 2: expired — removed without filling even though it would touch
		Assert.equals(0, b.evalBar(89.0, 92.0, 88.0, 2, 0).length);
		Assert.equals(0, b.pendingCount());
	}

	public function testInvalidSpecsThrow() {
		var b = new OrderBook();
		Assert.raises(function() b.place("long", { type: "limit" }, 0)); // px required
		Assert.raises(function() b.place("long", { type: "iceberg", px: 5 }, 0));
		Assert.raises(function() b.place("long", { type: "limit", px: -3 }, 0));
	}

	// ── OrderSim integration ────────────────────────────────────────────────

	public function testSlippageAppliedAgainstTrader() {
		var sim = new OrderSim(100000);
		sim.book.slippageBps = 100; // 1%
		sim.submit("long", { type: "market", qty: 10.0 }, 100.0, 0);
		sim.beginBar(100.0, 1, 101.0, 99.0);
		Assert.equals(1, sim.fills.length);
		Assert.floatEquals(101.0, sim.fills[0].price); // buy pays open * 1.01
		Assert.floatEquals(10.0, sim.position);
	}

	public function testLegacyVerbsNeverTouchBook() {
		var sim = new OrderSim(100000);
		sim.submit("long", 5.0, 100.0, 0);
		Assert.equals(0, sim.book.pendingCount());
		Assert.floatEquals(5.0, sim.position); // immediate close-fill, unchanged
		Assert.floatEquals(100.0, sim.fills[0].price);
	}

	/**
	 * Regression for a real, previously-undetected gap: every `long(qty)`/`short(qty)`/`flat()`
	 * strategy verb (the LEGACY immediate-fill path -- essentially every existing MuseScript
	 * strategy and every musescript.evo genome) traded at ZERO slippage/cost, even when
	 * `slippageBps` was configured, because only the spec-object order-book path
	 * (`beginBar`'s `book.evalBar` loop) ever called `slip()`. `slippageBps` still defaults to 0
	 * (so every caller that never sets it -- the whole rest of the test suite -- is unaffected),
	 * but a caller that DOES set it now sees the legacy path pay the cost too, exactly like the
	 * book path already did.
	 */
	public function testLegacyVerbsApplySlippageWhenConfigured() {
		var sim = new OrderSim(100000);
		sim.book.slippageBps = 100; // 1%
		sim.submit("long", 10.0, 100.0, 0);
		Assert.floatEquals(101.0, sim.fills[0].price, "a legacy long() should pay ask (open*1.01)");
		Assert.floatEquals(10.0, sim.position);
	}

	public function testLegacyShortAndFlatBothApplySlippage() {
		var sim = new OrderSim(100000);
		sim.book.slippageBps = 100; // 1%
		sim.submit("short", 10.0, 100.0, 0); // sell -> receives BELOW raw price
		Assert.floatEquals(99.0, sim.fills[0].price, "a legacy short() should receive bid (open*0.99)");
		sim.submit("flat", null, 100.0, 1); // covering a short is a BUY -> pays ABOVE raw price
		Assert.floatEquals(101.0, sim.fills[1].price, "covering a short should pay ask (open*1.01)");
	}

	/** Round-trip cost: a long entered and exited at the SAME raw price should show a REALIZED
	 * LOSS once both sides pay slippage -- this is the exact "free-trading" bias the fix closes
	 * (a strategy that looks profitable on a zero-cost backtest can be a net loser once entry AND
	 * exit both pay a realistic spread). */
	public function testRoundTripSlippageProducesRealizedLossAtFlatPrice() {
		var sim = new OrderSim(100000);
		sim.book.slippageBps = 100; // 1%
		sim.submit("long", 10.0, 100.0, 0); // pays 101
		sim.submit("flat", null, 100.0, 1); // receives 99
		var flatFill = sim.fills[1];
		Assert.isTrue(flatFill.pnl < 0, 'expected a round trip at the SAME raw price to realize a loss under cost, got pnl=${flatFill.pnl}');
	}

	/**
	 * Regression for a real, empirically-confirmed bug: pyramiding into an existing position
	 * (calling `long(qty)` repeatedly while already long -- a sticky, non-crossover entry
	 * condition staying true across many bars does exactly this) used to silently OVERWRITE
	 * `entryPrice` with only the LATEST fill, instead of tracking the true weighted-average cost
	 * basis. That directly corrupted `unrealized_pnl`/`unrealized_pnl_pct`-based risk-managed
	 * exits (stop-loss/take-profit) the moment pyramiding occurred. Confirmed via a standalone
	 * probe before this fix: long(1)@100, long(1)@110, long(1)@120 left entryPrice=120 (so
	 * unrealizedPnl at price 120 read 0) instead of the true average 110 (unrealizedPnl == 30).
	 */
	public function testPyramidedLongTracksWeightedAverageEntryPrice() {
		var sim = new OrderSim(100000);
		sim.submit("long", 1.0, 100.0, 0);
		sim.submit("long", 1.0, 110.0, 1);
		sim.submit("long", 1.0, 120.0, 2);
		Assert.equals(3, sim.trades);
		Assert.floatEquals(3.0, sim.position);
		Assert.floatEquals(110.0, sim.entryPrice, "expected the TRUE weighted-average cost basis, not just the latest fill");
		Assert.floatEquals(30.0, sim.unrealizedPnl(120.0));
	}

	public function testPyramidedShortTracksWeightedAverageEntryPrice() {
		var sim = new OrderSim(100000);
		sim.submit("short", 1.0, 100.0, 0);
		sim.submit("short", 1.0, 90.0, 1);
		sim.submit("short", 1.0, 80.0, 2);
		Assert.floatEquals(-3.0, sim.position);
		Assert.floatEquals(90.0, sim.entryPrice, "expected the TRUE weighted-average cost basis for a pyramided short");
		Assert.floatEquals(30.0, sim.unrealizedPnl(80.0)); // short favorable: (entry-price)*|qty| = (90-80)*3
	}

	/** A same-bar REVERSAL (short flips to long) is NOT pyramiding -- entryPrice should reset to
	 * the reversal fill's own price, not blend with the closed-out short's stale basis. */
	public function testReversalResetsEntryPriceRatherThanBlending() {
		var sim = new OrderSim(100000);
		sim.submit("short", 1.0, 100.0, 0);
		sim.submit("long", 1.0, 90.0, 1); // closes the short, opens a fresh long
		Assert.floatEquals(1.0, sim.position);
		Assert.floatEquals(90.0, sim.entryPrice, "a reversal's entryPrice must be its OWN fill price, not blended with the closed side");
	}

	// ── End-to-end through the language, interp vs compiled-js parity ───────

	static function trendBars():Array<Bar> {
		// open ramps 100→124; each bar's range is ±2 around open
		return [for (i in 0...25) bar(i, 100.0 + i, 102.0 + i, 98.0 + i, 101.0 + i)];
	}

	public function testSpecOrdersInterpJsParity() {
		var source = '
			@strategy("book")
			@on(bar) {
				if (bar_index == 2 && position() == 0 && orders_pending() == 0)
					long({ type: "stop", px: 105.0, qty: 10.0 });
				if (position() > 0 && orders_pending() == 0)
					flat({ type: "limit", px: 115.0 });
			}
		';
		var interpHarness = new HarnessContext();
		var interpResult = new MuseInterp(interpHarness).runBacktest(
			new MuseParser().parse(source), new BarFeed(trendBars()));
		Assert.equals(2, interpResult.trades); // stop entry + limit take-profit
		Assert.floatEquals(105.0, interpHarness.orders.fills[0].price);
		Assert.floatEquals(115.0, interpHarness.orders.fills[1].price);

		#if js
		var jsHarness = new HarnessContext();
		jsHarness.feed = new BarFeed(trendBars());
		TradeBuiltins.resetCrossState();
		var ex = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "js", strict: false });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testCancelAllBuiltin() {
		var source = '
			@strategy("cancel")
			@on(bar) {
				if (bar_index == 1) long({ type: "limit", px: 1.0 });
				if (bar_index == 2) orders_cancel_all();
			}
		';
		var harness = new HarnessContext();
		var result = new MuseInterp(harness).runBacktest(
			new MuseParser().parse(source), new BarFeed(trendBars()));
		Assert.equals(0, result.trades);
		Assert.equals(0, harness.orders.book.pendingCount());
	}
}
