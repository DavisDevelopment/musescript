package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;

/**
 * Candle-pattern vocabulary P0 (`candle_body`/`candle_dir`/wicks) + `bars_since`
 * (SPEC_CANDLE_PATTERN_DSL.md). Pinned on a controlled ALTERNATING bull/bear feed where each bar's
 * shape is known, so entries and exits both fire (avoids the always-true -> hold -> 0-trade trap).
 */
class TestCandleAndBarsSince extends Test {
	// Even bars bull (close>open), odd bars bear (close<open); both with small symmetric wicks.
	static function feed(n:Int):Array<Bar> {
		return [for (i in 0...n) i % 2 == 0
			? { open: 100.0, high: 102.0, low: 99.0, close: 101.0, volume: 1.0, time: i, index: i }   // bull
			: { open: 101.0, high: 102.0, low: 99.0, close: 100.0, volume: 1.0, time: i, index: i }]; // bear
	}

	static function trades(entry:String, ?exit:String):Int {
		var ex = exit != null ? exit : '!($entry)';
		var src = 'strategy C { onBar { when $entry: long() when $ex: flat() } }';
		// Reset per-run static callsite state (crossover/rising/bars_since slots) so runs don't leak
		// into each other -- GeneRunner.runOne does the same before every backtest.
		musescript.builtins.TradeBuiltins.resetCrossState();
		return new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(feed(120))).trades;
	}

	public function testCandleDirAndBodySign() {
		// Enter on a bull candle, exit on a bear candle -> a round trip every pair -> many trades.
		Assert.isTrue(trades("candle_dir(0) > 0", "candle_dir(0) < 0") > 0, "candle_dir is +1 on bull, -1 on bear");
		Assert.isTrue(trades("candle_body(0) > 0", "candle_body(0) < 0") > 0, "candle_body sign tracks the candle direction");
		// bull body = (101-100)/(102-99) = 1/3 ~ 0.33: a >0.3 gate still fires, a >0.9 gate never does.
		Assert.isTrue(trades("candle_body_abs(0) > 0.3", "candle_body_abs(0) < 0.3") > 0, "bull/bear body magnitude ~0.33");
		Assert.equals(0, trades("candle_body_abs(0) > 0.9"), "no candle here has a body > 0.9 of range");
	}

	public function testWicksAreNormalizedFractions() {
		// Every bar: range=3, wicks are 1 each -> upper/lower wick ~ 0.33, always < 0.9, never > 1.
		Assert.equals(0, trades("candle_upper_wick(0) > 0.9"), "upper wick is ~0.33 of range, never > 0.9");
		Assert.equals(0, trades("candle_lower_wick(0) > 1.1"), "a wick can never exceed the full range");
		Assert.isTrue(trades("candle_upper_wick(0) > 0.2", "candle_upper_wick(0) < 0.2") > 0, "upper wick ~0.33 fires a >0.2 gate");
	}

	public function testBarsSinceCountsAndSentinels() {
		// dir>0 is true on every bull (even) bar: bars_since(dir>0) == 0 there -> fires -> trades.
		Assert.isTrue(trades("bars_since(candle_dir(0) > 0) == 0", "bars_since(candle_dir(0) > 0) >= 1") > 0,
			"bars_since is 0 on the bar its condition holds");
		// A condition that never holds (dir is in {-1,0,1}) returns a large sentinel, so a `<= 3` gate never fires.
		Assert.equals(0, trades("bars_since(candle_dir(0) > 5) <= 3"), "bars_since of a never-true condition never satisfies a small bound");
	}
}
