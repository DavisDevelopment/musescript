package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ew.EwForecastHost;
import musescript.ew.LatticeForecastHost;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.ProjectionProvider;
import musescript.evo.ProjectionScore;
import musescript.harness.Bar;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Boundary X smoke: LatticeForecastHost.cloudAt → ProjectionProvider → SProj / Fitness.projScore.
 *
 * Proves co-evolved agents can consume EW projection clouds without Expand trading prelude
 * (PSHost columns are provider-backed; Expand still throws for host samplers).
 */
class TestEwHostProjection extends Test {
	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	/** Classic bull impulse: 100-110-105-120-112-125 */
	static function bullImpulse():Array<PivotPoint> {
		return [
			piv(100, -1, 0),
			piv(110, 1, 10),
			piv(105, -1, 20),
			piv(120, 1, 30),
			piv(112, -1, 40),
			piv(125, 1, 50)
		];
	}

	/** Flat synthetic tape long enough for horizon scoring around the seeded impulse. */
	static function tapeAroundImpulse(n:Int = 80):Array<Bar> {
		var bars:Array<Bar> = [];
		for (i in 0...n) {
			var px = 100.0 + i * 0.3;
			bars.push({
				open: px, high: px + 1, low: px - 1, close: px,
				volume: 1000, time: i * 60.0, index: i
			});
		}
		// Align late closes with impulse peak so coverage/IC see a rising level.
		if (n > 50) {
			bars[50].close = 125;
			bars[50].high = 126;
			bars[50].low = 124;
			bars[50].open = 124;
		}
		return bars;
	}

	static function seededHost():{host:LatticeForecastHost, graph:SwingGraph} {
		var g = new SwingGraph(0.02, 16);
		g.seedConfirmed(bullImpulse(), 51);
		var host = LatticeForecastHost.withGraph(g, null, 5);
		return {host: host, graph: g};
	}

	static function hostGenome():StrategyGenome {
		return {
			entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KSeries(SProj("ew_0", "spread")), KConst(1000.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "EW_HOST_PROJ",
			lineage: [],
			seedOrigin: null,
			projections: [ProjectionProvider.ewDecl("ew_0", 5, "lattice", 1)]
		};
	}

	public function testCloudFieldMapMatchesHost() {
		var s = seededHost();
		var host:EwForecastHost = s.host;
		var cloud = host.cloudAt(50);
		Assert.isTrue(cloud.samples >= 1);
		Assert.floatEquals(cloud.priceMid, ProjectionProvider.cloudField(cloud, "p50"), 1e-12);
		Assert.floatEquals(cloud.priceMid, ProjectionProvider.cloudField(cloud, "mean"), 1e-12);
		Assert.floatEquals(cloud.priceLo, ProjectionProvider.cloudField(cloud, "p05"), 1e-12);
		Assert.floatEquals(cloud.priceHi, ProjectionProvider.cloudField(cloud, "p95"), 1e-12);
		Assert.floatEquals(cloud.spread, ProjectionProvider.cloudField(cloud, "spread"), 1e-12);
		Assert.floatEquals(cloud.invalidatePrice, ProjectionProvider.cloudField(cloud, "inv"), 1e-12);
		Assert.floatEquals(cloud.countEntropy, ProjectionProvider.cloudField(cloud, "entropy"), 1e-12);
		Assert.floatEquals(cloud.nestScore, ProjectionProvider.cloudField(cloud, "nest"), 1e-12);
		Assert.isTrue(Math.isNaN(ProjectionProvider.cloudField(cloud, "nope")));
	}

	public function testBarsToCloudColumnsToProjScore() {
		var bars = tapeAroundImpulse(80);
		var s = seededHost();
		// Pre-seeded lattice: snapshot cloudAt per t without mutating pivots via onBar.
		var provider = new ProjectionProvider(s.host);
		var clouds = provider.snapshot(bars);
		Assert.equals(bars.length, clouds.length);
		Assert.isTrue(clouds[50].samples >= 1);
		Assert.isTrue(Math.isFinite(clouds[50].priceMid));
		Assert.isTrue(Math.isFinite(clouds[50].spread));
		Assert.isTrue(Math.isFinite(clouds[50].invalidatePrice));

		var mid = provider.fieldColumn("p50", bars);
		var spread = provider.fieldColumn("spread", bars);
		var inv = provider.fieldColumn("inv", bars);
		var entropy = provider.fieldColumn("entropy", bars);
		Assert.equals(bars.length, mid.length);
		Assert.isTrue(Math.isFinite(mid[50]));
		Assert.isTrue(Math.isFinite(spread[50]));
		Assert.isTrue(Math.isFinite(inv[50]));
		Assert.isTrue(Math.isFinite(entropy[50]));

		var g = hostGenome();
		// Referenced PSHost changes structural key vs projection-free genome.
		var g0 = hostGenome();
		g0.projections = null;
		g0.entryLong = BCmp(">", KConst(1.0), KConst(0.0));
		g0.exitLong = BCmp(">", KConst(0.0), KConst(1.0));
		Assert.notEquals(Canonical.structuralKey(g), Canonical.structuralKey(g0));

		var skill = ProjectionScore.skill(g.projections[0], g.params, bars, provider);
		Assert.isTrue(Math.isFinite(skill), "host proj skill should be finite, got " + skill);

		var cov = provider.bandCoverage(bars, 5);
		Assert.isTrue(Math.isFinite(cov), "band coverage should be finite when bands exist");

		var fr = new FitnessResult(true, 0, 0, 1000, "smoke");
		Fitness.attachProjectionScore(fr, g, bars, provider);
		Assert.isTrue(Math.isFinite(fr.projScore), "projScore should be finite");
		Assert.notNull(fr.projScores);
		Assert.equals(1, fr.projScores.length);
		Assert.isTrue(Math.isFinite(fr.projScores[0]));
	}

	public function testImpulseStillValidUnderHost() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		var arr = bullImpulse();
		for (i in 0...6) v[i] = arr[i];
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));
		var cloud = seededHost().host.cloudAt(50);
		Assert.floatEquals(100.0, cloud.invalidatePrice, 1e-9);
	}
}
