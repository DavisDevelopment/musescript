package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * `trail(dist)` — a peak-following trailing stop: true once price retraces `dist` price-units from
 * the best level reached since entry (peak high for a long). Pairs with `atr(close, n)` for a
 * volatility-scaled ratchet, but tested here with constant distances for a deterministic assertion:
 * a tiny trail exits on the smallest pullback (many round trips), an enormous trail never fires
 * (the position rides to the end of tape = a single trade).
 */
class TestTrailingStop extends Test {
	static function trades(dist:String):Int {
		var src = 'strategy T { onBar { when close > sma(close, 3): long() when trail($dist): flat() } }';
		var res = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), BarFeed.synthetic(400, 11));
		return res.trades;
	}

	public function testTightTrailExitsFarMoreThanLooseTrail() {
		var tight = trades("0.001");
		var loose = trades("1000000000.0"); // never retraces this far -> rides to end
		Assert.isTrue(tight > loose, 'a tight trail ($tight) should exit more often than a loose one ($loose)');
		Assert.isTrue(tight > 1, 'a 0.001 trail should fire on nearly every pullback, got $tight');
	}

	public function testEnormousTrailNeverFires() {
		// One entry, no trail exit ever triggered -> at most the single end-of-tape close.
		Assert.isTrue(trades("1000000000.0") <= 1, "an unreachable trail distance must not fire");
	}

	public function testTrailIsInertWhenFlat() {
		// A strategy that never enters (impossible entry) must run cleanly with a trail exit present:
		// trail() returns false while flat, so no spurious flat() / error.
		var src = "strategy NeverIn { onBar { when close < 0: long() when trail(1.0): flat() } }";
		var res = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), BarFeed.synthetic(200, 5));
		Assert.equals(0, res.trades, "trail must be inert while flat (no entries -> no trades, no crash)");
	}
}
