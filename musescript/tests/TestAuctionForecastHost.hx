package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.ew.EwForecastHost;
import musescript.ew.auction.AuctionForecastHost;
import musescript.ew.auction.VolumeProfile;

/**
 * AuctionForecastHost: value-area cloud + balance/discovery classification.
 * Includes NVDA smoke (non-NaN clouds) and breakout hit-rate metrics.
 */
class TestAuctionForecastHost extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return {open: o, high: h, low: l, close: c, volume: v, time: i, index: i};
	}

	/** Synthetic balance: price oscillates inside a tight band with volume. */
	static function balanceTape(n:Int):Array<Bar> {
		return [for (i in 0...n) {
			var mid = 100.0 + Math.sin(i * 0.4) * 1.5;
			bar(mid, mid + 1.0, mid - 1.0, mid, 2000, i);
		}];
	}

	/** Synthetic discovery-up: build value then break above. */
	static function discoveryUpTape():Array<Bar> {
		var out:Array<Bar> = [];
		for (i in 0...20) {
			var mid = 100.0 + Math.sin(i * 0.3) * 1.0;
			out.push(bar(mid, mid + 1.2, mid - 1.2, mid, 3000, i));
		}
		for (i in 20...30) {
			var mid = 104.0 + (i - 20) * 0.8;
			out.push(bar(mid - 0.3, mid + 0.5, mid - 0.5, mid, 2500, i));
		}
		return out;
	}

	public function testWithBarsEmitsFiniteCloud() {
		var bars = balanceTape(40);
		var host:EwForecastHost = AuctionForecastHost.withBars(bars, 20, 40, 0.70, 5);
		var cloud = host.cloudAt(30);
		Assert.equals(1, cloud.samples);
		Assert.isTrue(Math.isFinite(cloud.priceLo));
		Assert.isTrue(Math.isFinite(cloud.priceHi));
		Assert.isTrue(Math.isFinite(cloud.priceMid));
		Assert.isTrue(Math.isFinite(cloud.spread));
		Assert.isTrue(Math.isFinite(cloud.probUp));
		Assert.isTrue(cloud.priceHi >= cloud.priceLo);
		Assert.isTrue(cloud.priceMid >= cloud.priceLo - 1e-9);
		Assert.isTrue(cloud.priceMid <= cloud.priceHi + 1e-9);
		Assert.floatEquals(cloud.spread, cloud.priceHi - cloud.priceLo, 1e-9);
	}

	public function testEmptyBeforeWarmup() {
		var bars = balanceTape(10);
		var host = AuctionForecastHost.withBars(bars, 20, 40, 0.70, 5);
		var cloud = host.cloudAt(5);
		Assert.equals(0, cloud.samples);
		Assert.isTrue(Math.isNaN(cloud.priceLo));
		Assert.equals(0, host.topCounts(5, 3).length);
	}

	public function testBalanceRegimeInsideValueArea() {
		var bars = balanceTape(40);
		var host = AuctionForecastHost.withBars(bars, 20, 40, 0.70, 5);
		var cloud = host.cloudAt(30);
		Assert.equals(1.0, cloud.labelCode);
		var counts = host.topCounts(30, 3);
		Assert.isTrue(counts.length >= 1);
		Assert.equals(AuctionForecastHost.LABEL_BALANCE, counts[0].label);
		Assert.isTrue(counts[0].mass > 0.4);
	}

	public function testDiscoveryUpBreakout() {
		var bars = discoveryUpTape();
		var host = AuctionForecastHost.withBars(bars, 15, 40, 0.70, 5);
		var t = bars.length - 1;
		var cloud = host.cloudAt(t);
		Assert.equals(1, cloud.samples);
		Assert.isTrue(cloud.probUp > 0.4, 'probUp ${cloud.probUp} should lean up on breakout');
		Assert.equals(2.0, cloud.labelCode);
		var counts = host.topCounts(t, 3);
		Assert.equals(AuctionForecastHost.LABEL_DISCOVERY_UP, counts[0].label);
	}

	public function testCloudMapsValueAreaEdges() {
		var bars = balanceTape(40);
		var host = AuctionForecastHost.withBars(bars, 20, 40, 0.70, 5);
		var levels = VolumeProfile.fromBars(bars, 20, 40, 0.70, 30);
		var cloud = host.cloudAt(30);
		Assert.floatEquals(levels.vaLow, cloud.priceLo, 1e-12);
		Assert.floatEquals(levels.vaHigh, cloud.priceHi, 1e-12);
		Assert.floatEquals(levels.poc, cloud.priceMid, 1e-12);
	}

	public function testPhiKeyRoundTrip() {
		var host = new AuctionForecastHost(20, 50, 0.70, 5, "auction-phi-v1");
		Assert.equals("auction-phi-v1", host.phiKey());
	}

	public function testNvdaSmokeNonNanClouds() {
		var path = resolveNvda();
		Assert.isTrue(path != null, "data/real/nvda.csv not found");
		var bars = OhlcvCsv.load(path);
		Assert.isTrue(bars.length > 100, 'NVDA bar count ${bars.length}');

		var host = AuctionForecastHost.withBars(bars, 20, 50, 0.70, 5, "auction-nvda");
		var checked = 0;
		var finite = 0;
		var step = Std.int(Math.max(1, Math.ffloor(bars.length / 40)));
		var t = 40;
		while (t < bars.length) {
			var cloud = host.cloudAt(t);
			checked++;
			if (cloud.samples >= 1
				&& Math.isFinite(cloud.priceLo)
				&& Math.isFinite(cloud.priceHi)
				&& Math.isFinite(cloud.priceMid)
				&& Math.isFinite(cloud.spread)
				&& Math.isFinite(cloud.probUp)
			) {
				finite++;
				Assert.isTrue(cloud.priceHi >= cloud.priceLo);
			}
			t += step;
		}
		Assert.isTrue(finite > 0, "expected at least one finite NVDA cloud");
		Assert.isTrue(finite == checked, 'all sampled clouds finite: $finite/$checked');
		Sys.println('[auction-nvda-smoke] bars=${bars.length} sampled=$checked finite=$finite');
	}

	/**
	 * Score where price-capture null is weak: breakout call hit-rate + value-center drift.
	 * Discovery-up/down calls vs subsequent price direction over horizon H.
	 */
	public function testNvdaBreakoutHitRate() {
		var path = resolveNvda();
		Assert.isTrue(path != null, "data/real/nvda.csv not found");
		var bars = OhlcvCsv.load(path);
		var window = 20;
		var horizon = 5;
		var host = AuctionForecastHost.withBars(bars, window, 50, 0.70, horizon);

		var upCalls = 0;
		var upHits = 0;
		var downCalls = 0;
		var downHits = 0;
		var balanceBars = 0;
		var discoveryBars = 0;
		var pocDriftSum = 0.0;
		var pocDriftN = 0;

		var t = window;
		while (t + horizon < bars.length) {
			var cloud = host.cloudAt(t);
			if (cloud.samples < 1) {
				t++;
				continue;
			}
			var regime = host.lastRegimeLabel();
			var levelsNow = host.lastProfile();
			var levelsLater = VolumeProfile.fromBars(bars, window, 50, 0.70, t + horizon);
			if (levelsNow != null && Math.isFinite(levelsNow.poc) && Math.isFinite(levelsLater.poc)) {
				pocDriftSum += Math.abs(levelsLater.poc - levelsNow.poc);
				pocDriftN++;
			}

			if (regime == AuctionForecastHost.LABEL_BALANCE) {
				balanceBars++;
			} else {
				discoveryBars++;
			}

			var ret = bars[t + horizon].close - bars[t].close;
			if (regime == AuctionForecastHost.LABEL_DISCOVERY_UP) {
				upCalls++;
				if (ret > 0) upHits++;
			} else if (regime == AuctionForecastHost.LABEL_DISCOVERY_DOWN) {
				downCalls++;
				if (ret < 0) downHits++;
			}
			t++;
		}

		var upRate = upCalls > 0 ? upHits / upCalls : Math.NaN;
		var downRate = downCalls > 0 ? downHits / downCalls : Math.NaN;
		var allCalls = upCalls + downCalls;
		var allHits = upHits + downHits;
		var hitRate = allCalls > 0 ? allHits / allCalls : Math.NaN;
		var avgPocDrift = pocDriftN > 0 ? pocDriftSum / pocDriftN : Math.NaN;

		Sys.println('[auction-breakout] balance=$balanceBars discovery=$discoveryBars');
		Sys.println('[auction-breakout] up_calls=$upCalls up_hits=$upHits up_hit_rate=${pct(upRate)}');
		Sys.println('[auction-breakout] down_calls=$downCalls down_hits=$downHits down_hit_rate=${pct(downRate)}');
		Sys.println('[auction-breakout] combined_hit_rate=${pct(hitRate)} ($allHits/$allCalls)');
		Sys.println('[auction-breakout] avg_poc_drift_over_H$horizon=${fmt(avgPocDrift)}');

		Assert.isTrue(allCalls > 0, "expected some discovery breakout calls on NVDA");
		Assert.isTrue(Math.isFinite(hitRate));
		// Not requiring edge vs 50% — report the metric; just ensure evaluation ran.
		Assert.isTrue(hitRate >= 0 && hitRate <= 1);
	}

	static function resolveNvda():Null<String> {
		for (p in ["data/real/nvda.csv", "muse-script/data/real/nvda.csv", "../muse-script/data/real/nvda.csv"]) {
			if (OhlcvCsv.exists(p)) return p;
		}
		return null;
	}

	static function pct(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.ffloor(x * 1000 + 0.5) / 10) + "%";
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.ffloor(x * 1e6 + 0.5) / 1e6);
	}
}
