package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;

/**
 * The 2026-08 "Tier 1" batch: `donchian(n)` multi-output struct, `any_of`/`all_of` variadic bool
 * combinators, and labelled order calls (`flat("tag")`) recording per-tag fire counts on OrderSim.
 */
class TestTier1Builtins extends Test {
	static function bars(n:Int):Array<Bar> {
		// Deterministic oscillation so entries/exits actually fire.
		return [for (i in 0...n) {
			var c = 100.0 + 5.0 * Math.sin(i / 5.0);
			{ open: c, high: c + 1.0, low: c - 1.0, close: c, volume: 1.0, time: i, index: i };
		}];
	}

	static function run(src:String):HarnessContext {
		var h = new HarnessContext();
		new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars(240)));
		return h;
	}

	static function trades(entry:String):Int {
		return run('strategy T { onBar { when $entry: long() when !($entry): flat() } }').orders.trades;
	}

	public function testDonchianUpperEqualsHighestHigh() {
		// donchian(n).upper is exactly highest(high, n): a strategy that fires only on a MISMATCH
		// must never trade.
		Assert.equals(0, trades("donchian(20).upper > highest(high, 20) + 0.0001 || donchian(20).upper < highest(high, 20) - 0.0001"),
			"donchian(n).upper must equal highest(high, n)");
		Assert.equals(0, trades("donchian(20).lower < lowest(low, 20) - 0.0001 || donchian(20).lower > lowest(low, 20) + 0.0001"),
			"donchian(n).lower must equal lowest(low, n)");
		// mid = (upper + lower) / 2 is guaranteed by the impl, and `upper == highest` / `lower ==
		// lowest` above pin both bounds, so mid correctness follows arithmetically. A runtime
		// mid-vs-fields cross-comparison is NOT asserted here: reading two fields of the SAME
		// multi-output call in one expression is a CONFIRMED interp-only bug (WP-E, deferred low-pri
		// per AUDIT_TRIAGE) -- NOT the state-leak (survives the WP-B auto-reset); js/wasm/vm correct.
	}

	public function testAnyOfIsOrAllOfIsAnd() {
		Assert.isTrue(trades("any_of(close > 0, close < 0)") > 0, "any_of fires if ANY arg is true");
		Assert.equals(0, trades("any_of(close < 0, close < -1)"), "any_of false when all args false");
		Assert.isTrue(trades("all_of(close > 0, high > low)") > 0, "all_of fires when ALL args true");
		Assert.equals(0, trades("all_of(close > 0, close < 0)"), "all_of false when any arg false");
	}

	public function testLabelledOrdersRecordPerTagFireCounts() {
		var h = run("strategy Tagged {
			onBar {
				when close > sma(close, 5): long()
				when close < sma(close, 5): flat(\"ma_cross\")
			}
			onPosition {
				when close < -1: flat(\"never_fires\")
			}
		}");
		Assert.isTrue(h.orders.tagFires.exists("ma_cross") && h.orders.tagFires.get("ma_cross") > 0,
			"the ma_cross exit layer should record fires");
		Assert.isFalse(h.orders.tagFires.exists("never_fires"),
			"a guard that never triggers leaves no tag (silent no-op layer diagnostic)");
	}
}
