package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.ew.HostLeakageProbe;
import musescript.ew.HostWarmup;
import musescript.ew.LatticeForecastHost;
import musescript.ew.McmcForecastHost;
import musescript.ew.RegimeForecastHost;
import musescript.ew.auction.AuctionForecastHost;
import musescript.ew.mcmc.DetRng;
import musescript.indicators.geom.SwingGraphStack;
import musescript.evo.ProjectionProvider;
import musescript.evo.ProjectionScore;
import musescript.evo.ProjKind;
import musescript.evo.StrategyGenome;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.Expand;
import haxe.Int64;

/**
 * Bucket C — leakage & PIT discipline standing tests (PIPELINE_HARDENING_TODO.md).
 * C1 production-host probes · C2 target boundaries · C3 decorate/materialize · C4 warmup.
 */
class TestPitDiscipline extends Test {
	static function synthBars(n:Int, ?seed:Int = 7):Array<Bar> {
		var rng = new DetRng(Int64.ofInt(seed), Int64.ofInt(0xC1C1));
		var out:Array<Bar> = [];
		var px = 100.0;
		for (i in 0...n) {
			var r = (rng.nextUnit() - 0.48) * 0.015;
			var o = px;
			px *= (1 + r);
			out.push({
				open: o, high: Math.max(o, px) * 1.002, low: Math.min(o, px) * 0.998,
				close: px, volume: 1000 + rng.nextInt(200), time: i + 0.0, index: i
			});
		}
		return out;
	}

	static function rampBars(n:Int):Array<Bar> {
		return [for (i in 0...n) {
			var c = 100.0 + i;
			({open: c, high: c + 1, low: c - 1, close: c, volume: 1000.0, time: i + 0.0, index: i} : Bar);
		}];
	}

	// ── C1: production host leakage probes ────────────────────────────────────

	public function testLatticeHostPassesLeakageProbe() {
		var bars = synthBars(80, 11);
		var t = 40;
		var err = HostLeakageProbe.probe(function(_) {
			var stack = new SwingGraphStack(0.02, 0.05, 16);
			return LatticeForecastHost.withStack(stack, null, 3);
		}, bars, t, false);
		Assert.isNull(err, 'Lattice leak: $err');
	}

	public function testMcmcHostPassesLeakageProbe() {
		var bars = synthBars(80, 12);
		var t = 40;
		var err = HostLeakageProbe.probe(function(_) {
			var stack = new SwingGraphStack(0.02, 0.05, 16);
			return McmcForecastHost.withStack(stack, null, 3, 4, 42);
		}, bars, t, false);
		Assert.isNull(err, 'Mcmc leak: $err');
	}

	public function testRegimeHostPassesLeakageProbe() {
		var bars = synthBars(100, 13);
		var t = 50;
		// Small MH budget for a fast standing test; fullStream exercises t-truncation after past-t bars.
		var err = HostLeakageProbe.probe(
			_ -> new RegimeForecastHost(7, 2, 5, 40, 80, 30, 20, 0.97),
			bars, t, true
		);
		Assert.isNull(err, 'Regime leak: $err');
	}

	public function testAuctionHostPassesLeakageProbe() {
		var bars = synthBars(60, 14);
		var t = 35;
		// Auction retains the tape and claims assemble(t) uses ≤ t only — fullStream probe.
		var err = HostLeakageProbe.probe(
			tape -> AuctionForecastHost.withBars(tape, 15, 30, 0.70, 5),
			bars, t, true
		);
		Assert.isNull(err, 'Auction leak: $err');
	}

	public function testProductionHostsEmitInvariantClouds() {
		var bars = synthBars(70, 15);
		var t = 45;
		var hosts:Array<{name:String, h:musescript.ew.EwForecastHost}> = [
			{
				name: "lattice",
				h: {
					var s = new SwingGraphStack(0.02, 0.05, 16);
					LatticeForecastHost.withStack(s, null, 3);
				}
			},
			{
				name: "mcmc",
				h: {
					var s = new SwingGraphStack(0.02, 0.05, 16);
					McmcForecastHost.withStack(s, null, 3, 4, 1);
				}
			},
			{name: "regime", h: new RegimeForecastHost(3, 2, 5, 40, 60, 20, 16, 0.97)},
			{name: "auction", h: new AuctionForecastHost(15, 30, 0.70, 5)}
		];
		for (pack in hosts) {
			for (i in 0...t + 1) pack.h.onBar(bars[i], i);
			var c = pack.h.cloudAt(t);
			var inv = HostLeakageProbe.checkInvariants(c);
			Assert.isNull(inv, '${pack.name} invariants: $inv');
		}
	}

	// ── C2: benchmark target boundaries ───────────────────────────────────────

	public function testRealizedTargetExcludesLastHBars() {
		var bars = rampBars(20);
		var h = 3;
		var y = ProjectionScore.realizedTarget(bars, PLevel, h);
		Assert.equals(20, y.length);
		for (i in 0...(20 - h)) Assert.isTrue(Math.isFinite(y[i]));
		for (i in (20 - h)...20) Assert.isTrue(Math.isNaN(y[i]), 'last-H bar $i must be NaN');
	}

	public function testRealizedTargetUsesFutureNotPresent() {
		var bars = rampBars(30);
		var t = 10;
		var h = 5;
		var lvl = ProjectionScore.realizedTarget(bars, PLevel, h);
		// Off-by-one that lets t see t would set y[t] = close[t]; must be close[t+h].
		Assert.floatEquals(bars[t + h].close, lvl[t]);
		Assert.isTrue(lvl[t] != bars[t].close);
		var dir = ProjectionScore.realizedTarget(bars, PDirection, h);
		Assert.floatEquals(1.0, dir[t]); // rising ramp
		var ret = ProjectionScore.realizedTarget(bars, PReturn, h);
		Assert.floatEquals(bars[t + h].close / bars[t].close - 1.0, ret[t]);
	}

	public function testForwardRangeStartsStrictlyAfterT() {
		var bars = rampBars(20);
		var t = 5;
		var h = 3;
		var y = ProjectionScore.realizedTarget(bars, PRange, h);
		// Range over bars[t+1 .. t+h] on a unit ramp: high=(t+h)+1, low=(t+1)-1 → span = h+2
		var expectHi = bars[t + h].high;
		var expectLo = bars[t + 1].low;
		Assert.floatEquals(expectHi - expectLo, y[t]);
		// Mutating bar t must NOT change forward range at t
		var bars2 = rampBars(20);
		bars2[t] = {
			open: 999, high: 9999, low: -9999, close: 999,
			volume: 1, time: t + 0.0, index: t
		};
		var y2 = ProjectionScore.realizedTarget(bars2, PRange, h);
		Assert.floatEquals(y[t], y2[t], 'forwardRange must ignore bar t');
	}

	public function testMutatingFutureChangesTargetMutatingPastPredictorOk() {
		var bars = rampBars(25);
		var t = 8;
		var h = 4;
		var y0 = ProjectionScore.realizedTarget(bars, PLevel, h)[t];
		var barsFut = rampBars(25);
		barsFut[t + h] = {
			open: 500, high: 501, low: 499, close: 500,
			volume: 1, time: (t + h) + 0.0, index: t + h
		};
		var yFut = ProjectionScore.realizedTarget(barsFut, PLevel, h)[t];
		Assert.isTrue(yFut != y0, "future close must move PLevel target");

		var barsPast = rampBars(25);
		barsPast[t] = {
			open: 1, high: 2, low: 0, close: 1,
			volume: 1, time: t + 0.0, index: t
		};
		var yPast = ProjectionScore.realizedTarget(barsPast, PLevel, h)[t];
		Assert.floatEquals(y0, yPast, "PLevel target must not depend on close[t]");
	}

	// ── C3: decorateBars / materialize causality ──────────────────────────────

	public function testDecorateColumnEqualsStreamingCloudAt() {
		var bars = synthBars(50, 21);
		var stack = new SwingGraphStack(0.02, 0.05, 16);
		var host = LatticeForecastHost.withStack(stack, null, 3);
		var g:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "PIT_DECORATE",
			lineage: [],
			seedOrigin: null,
			projections: [ProjectionProvider.ewDecl("ew_0", 5, "lattice", 1)]
		};
		var provider = new ProjectionProvider(host);
		var decorated = provider.decorateBars(bars, g, true);
		var col = Expand.projRef("ew_0", "p50");
		Assert.equals(bars.length, decorated.length);

		// Independent streaming host — same stack params
		var stack2 = new SwingGraphStack(0.02, 0.05, 16);
		var host2 = LatticeForecastHost.withStack(stack2, null, 3);
		var compared = 0;
		for (t in 0...bars.length) {
			host2.onBar(bars[t], t);
			var cloud = host2.cloudAt(t);
			var expected = ProjectionProvider.cloudField(cloud, "p50");
			var got = decorated[t].data != null && decorated[t].data.exists(col)
				? decorated[t].data.get(col) : Math.NaN;
			if (Math.isNaN(expected) && Math.isNaN(got)) {
				compared++;
				continue;
			}
			Assert.floatEquals(expected, got, 1e-12);
			compared++;
		}
		Assert.isTrue(compared == bars.length, 'must compare every bar, got $compared');
	}

	public function testMaterializeNeverPreloadsFutureColumns() {
		var bars = synthBars(40, 22);
		var stack = new SwingGraphStack(0.02, 0.05, 16);
		var host = LatticeForecastHost.withStack(stack, null, 3);
		var provider = new ProjectionProvider(host);
		var clouds = provider.materialize(bars);
		// Prefix materialize must match full-tape clouds at each t (causal streaming).
		var stackP = new SwingGraphStack(0.02, 0.05, 16);
		var hostP = LatticeForecastHost.withStack(stackP, null, 3);
		var providerP = new ProjectionProvider(hostP);
		var prefix = bars.slice(0, 25);
		var cloudsP = providerP.materialize(prefix);
		for (t in 0...prefix.length) {
			Assert.floatEquals(cloudsP[t].priceMid, clouds[t].priceMid, 1e-12,
				'prefix materialize diverged at t=$t — future preload?');
		}
	}

	// ── C4: warmup honesty ────────────────────────────────────────────────────

	public function testWarmupGuardRejectsEarlyAnchors() {
		Assert.isFalse(HostWarmup.isLegalAnchor(10, 60, 5, 20, 500));
		Assert.isFalse(HostWarmup.isLegalAnchor(60, 60, 5, 20, 70)); // no room for horizon
		Assert.isTrue(HostWarmup.isLegalAnchor(60, 60, 5, 20, 200));
		Assert.isFalse(HostWarmup.isLegalAnchor(61, 60, 5, 20, 200)); // off step grid
		Assert.isTrue(HostWarmup.isLegalAnchor(65, 60, 5, 20, 200));
	}

	public function testRegimeWarmupFloor() {
		Assert.isFalse(HostWarmup.regimeReady(29));
		Assert.isTrue(HostWarmup.regimeReady(30));
		var host = new RegimeForecastHost(1, 2, 5, 40, 40, 15, 10, 0.97);
		for (i in 0...20) host.onBar({
			open: 100, high: 101, low: 99, close: 100.0 + i * 0.1,
			volume: 1, time: i + 0.0, index: i
		}, i);
		Assert.equals(0, host.cloudAt(19).samples, "below MIN_RETURNS → empty cloud");
	}

	public function testAuctionWarmupFloor() {
		Assert.isFalse(HostWarmup.auctionReady(10, 20));
		Assert.isTrue(HostWarmup.auctionReady(19, 20));
		var bars = synthBars(25, 3);
		var host = AuctionForecastHost.withBars(bars, 20, 30, 0.70, 5);
		Assert.equals(0, host.cloudAt(10).samples);
		Assert.equals(1, host.cloudAt(19).samples);
	}

	public function testBenchmarkWarmupDefaultsDocumented() {
		Assert.equals(60, HostWarmup.EW_LATTICE_BENCHMARK);
		Assert.equals(180, HostWarmup.REGIME_BENCHMARK);
		Assert.equals(120, HostWarmup.AUCTION_BENCHMARK);
		Assert.equals(30, HostWarmup.REGIME_MIN_RETURNS);
	}
}
