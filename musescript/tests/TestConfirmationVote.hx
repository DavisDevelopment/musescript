package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * `count_true(...)` — variadic bool->number: counts how many of its boolean arguments hold, so
 * `count_true(a, b, c) >= 2` is an N-of-M confirmation gate and `count_true(x)` is a plain 0/1
 * coercion. On a synthetic feed `close > 0` is always true and `close < 0` always false, so the
 * argument truth pattern is known and the vote count is asserted directly via whether the strategy
 * trades under a given threshold.
 */
class TestConfirmationVote extends Test {
	static function trades(entry:String):Int {
		var src = 'strategy V { onBar { when $entry: long() when !($entry): flat() } }';
		var res = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), BarFeed.synthetic(400, 11));
		return res.trades;
	}

	public function testTwoOfThreeThresholdCounts() {
		// two args true (close>0, close>0), one false (close<0) => count is exactly 2.
		Assert.isTrue(trades("count_true(close > 0, close > 0, close < 0) >= 2") > 0, ">=2 of a 2-true vote should fire");
		Assert.equals(0, trades("count_true(close > 0, close > 0, close < 0) >= 3"), ">=3 of a 2-true vote must not fire");
	}

	public function testAllFalseAndAllTrueBounds() {
		Assert.equals(0, trades("count_true(close < 0, close < 0) >= 1"), "no true args => count 0");
		Assert.isTrue(trades("count_true(close > 0, close > 0) >= 2") > 0, "all true => count == arity");
	}

	public function testSingleArgIsBoolToNumberCoercion() {
		// count_true(x) >= 1 is exactly x; count_true(x) is 1.0 when x else 0.0.
		Assert.isTrue(trades("count_true(close > 0) >= 1") > 0, "count_true(true) == 1");
		Assert.equals(0, trades("count_true(close > 0) >= 2"), "count_true of one arg can never reach 2");
	}
}
