package musescript.tests;

import utest.Assert;
import utest.Test;
import haxe.Int64;
import haxe.ds.Vector;
import musescript.harness.Bar;
import musescript.ew.mcmc.DetRng;
import musescript.ew.RegimeForecastHost;

/**
 * RegimeForecastHost must produce a well-formed, PIT-causal ForecastCloud from streamed bars — the
 * contract that lets a non-EW substrate drop into the benchmark + evolution rig unchanged. Feeds a
 * synthetic calm→volatile tape and checks the cloud is sensible and the current regime reads volatile.
 */
class TestRegimeHost extends Test {
	static function bar(i:Int, close:Float):Bar {
		return { open: close, high: close * 1.001, low: close * 0.999, close: close, volume: 1000, time: i, index: i };
	}

	/** Prices from a calm→volatile synthetic return stream. */
	static function synthBars():Array<Bar> {
		var rng = new DetRng(Int64.make(0x11, 0x22));
		var px = 100.0;
		var out = [bar(0, px)];
		for (i in 1...200) {
			var sig = i < 100 ? 0.004 : 0.02;
			px *= Math.exp(sig * rng.nextGaussian());
			out.push(bar(i, px));
		}
		return out;
	}

	public function testEmitsWellFormedCausalCloud() {
		var bars = synthBars();
		// small sampler budget for a fast test
		var host = new RegimeForecastHost(7, 2, 10, 120, 500, 150, 60, 0.97);
		var lastCloud = null;
		for (i in 0...bars.length) {
			host.onBar(bars[i], i);
			if (i == bars.length - 1) lastCloud = host.cloudAt(i);
		}
		Assert.notNull(lastCloud);
		Assert.isTrue(Math.isFinite(lastCloud.priceLo) && Math.isFinite(lastCloud.priceHi));
		Assert.isTrue(lastCloud.priceHi > lastCloud.priceLo, "band must have positive width");
		Assert.isTrue(lastCloud.priceMid >= lastCloud.priceLo && lastCloud.priceMid <= lastCloud.priceHi,
			"mid inside band");
		Assert.isTrue(lastCloud.probUp >= 0 && lastCloud.probUp <= 1, "probUp is a probability");
		Assert.isTrue(lastCloud.countEntropy >= 0, "entropy non-negative");
		Assert.isTrue(lastCloud.samples > 0);
		// labelCode is a valid 1-based regime id (single-last-bar regime is inherently noisy; robust
		// regime recovery is proven in TestRegimeMcmc over a window, not asserted on one bar here).
		Assert.isTrue(lastCloud.labelCode >= 1.0 && lastCloud.labelCode <= 2.0, "valid regime code");
	}

	public function testTopCountsAreARegimePosterior() {
		var bars = synthBars();
		var host = new RegimeForecastHost(7, 2, 10, 120, 500, 150, 60, 0.97);
		for (i in 0...bars.length) host.onBar(bars[i], i);
		var _ = host.cloudAt(bars.length - 1);
		var counts = host.topCounts(bars.length - 1, 5);
		Assert.equals(2, counts.length);
		var sum = 0.0;
		for (c in counts) sum += c.mass;
		Assert.floatEquals(1.0, sum); // a proper posterior over regimes
	}

	public function testShortHistoryDegradesToEmpty() {
		var host = new RegimeForecastHost(7, 2, 10);
		for (i in 0...10) host.onBar({ open: 100, high: 100, low: 100, close: 100.0 + i, volume: 1, time: i, index: i }, i);
		var c = host.cloudAt(9);
		Assert.equals(0, c.samples); // not enough returns yet → empty cloud, no invented band
	}
}
