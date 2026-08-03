package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.harness.BarFeed;
import musescript.harness.HonestOptimize;

/**
 * Explicit-list parameter sweep: `param x = v { values: [a, b, c] }`. The only way to grid-search a
 * NON-uniform set (e.g. Fibonacci window lengths) that min/max/step can't express. Asserts the
 * honest optimizer enumerates exactly the cartesian product of the declared lists.
 */
class TestParamSweep extends Test {
	static function trials(src:String):Int {
		var bars = BarFeed.synthetic(300, 7).all();
		var res = HonestOptimize.search(src, bars, { seed: 1, method: "grid", tier: "js", minTrades: 1 });
		return Std.int(Reflect.field(res, "trials"));
	}

	public function testExplicitValuesListSweepsExactlyThoseCombos() {
		var src = "
			strategy Grid {
				param fast = 8 { values: [3, 5, 8, 13] }
				param slow = 34 { values: [34, 55] }
				onBar {
					when close > sma(close, fast) && close > sma(close, slow): long()
					when close < sma(close, slow): flat()
				}
			}
		";
		Assert.equals(8, trials(src), "4 fast x 2 slow explicit values => 8 grid trials");
	}

	public function testSingleValuesListSweepsItsLength() {
		var src = "
			strategy One {
				param look = 8 { values: [5, 8, 13, 21, 34] }
				onBar {
					when close > sma(close, look): long()
					when close < sma(close, look): flat()
				}
			}
		";
		Assert.equals(5, trials(src), "a 5-value non-uniform Fib list => 5 trials");
	}
}
