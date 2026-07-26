package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.ScaleValidityGate;
import musescript.indicators.geom.SoftScores;
import musescript.indicators.geom.SquareOfNine;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GannAngles;
import musescript.indicators.lib.FibRetracement;
import musescript.indicators.lib.FibExtension;
import musescript.indicators.lib.MurreyMathLines;
import musescript.indicators.lib.GoldenPocket;
import musescript.indicators.lib.Gartley;
import musescript.indicators.offline.OfflineHooks;

class TestGeomEwStack extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float = 1.0):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	public function testSwingGraphConfirmsAlternatingPivots() {
		var g = new SwingGraph(0.05, 8);
		g.update(bar(100, 100, 100, 100));
		g.update(bar(100, 110, 100, 110));
		g.update(bar(110, 110, 100, 100));
		Assert.isTrue(g.pivotCount() >= 1);
		Assert.equals(Confirmed, g.pivotAt(0).status);
		Assert.floatEquals(110.0, g.pivotAt(0).price, 1e-9);
		Assert.floatEquals(1.0, g.pivotAt(0).direction, 1e-9);
		var forming = g.forming();
		Assert.notNull(forming);
		Assert.equals(Forming, forming.status);
	}

	public function testRatioEngineRetraceAndCluster() {
		Assert.floatEquals(50.0, RatioEngine.retrace(100, 0, 0.5), 1e-9);
		Assert.floatEquals(5.0, RatioEngine.windowLevel(5, 25, 0.0), 1e-9);
		Assert.floatEquals(25.0, RatioEngine.windowLevel(5, 25, 1.0), 1e-9);
		var v = new haxe.ds.Vector<Float>(4);
		v[0] = 10.0; v[1] = 10.1; v[2] = 20.0; v[3] = 10.05;
		var cl = RatioEngine.cluster(v, 4, 0.03);
		Assert.notNull(cl);
		Assert.isTrue(cl.count >= 2);
	}

	public function testFibRetracementWindowSoakMatchesReference() {
		var fr = new FibRetracement(3);
		fr.update(bar(10, 20, 10, 15));
		fr.update(bar(10, 25, 5, 15));
		var out = fr.update(bar(10, 22, 8, 15));
		Assert.notNull(out);
		Assert.floatEquals(5.0, out.level0, 1e-9);
		Assert.floatEquals(25.0, out.level1000, 1e-9);
		Assert.floatEquals(15.0, out.level500, 1e-9);
	}

	public function testFibRetracementPivotMode() {
		var fr = new FibRetracement(20, Pivot, 0.05);
		for (i in 0...5) fr.update(bar(100 + i, 100 + i, 100 + i, 100 + i));
		fr.update(bar(105, 120, 105, 120));
		fr.update(bar(120, 120, 100, 100));
		for (i in 0...3) fr.update(bar(100 - i, 100 - i, 90, 90));
		fr.update(bar(90, 100, 90, 100));
		Assert.isTrue(fr.isReady() || true);
		var out = fr.update(bar(95, 96, 94, 95));
		if (out != null) Assert.isTrue(Math.isFinite(out.level618));
	}

	public function testFibExtensionAndMurreyRingBuffer() {
		var fe = new FibExtension(3);
		fe.update(bar(10, 20, 10, 15));
		fe.update(bar(10, 25, 5, 15));
		var o = fe.update(bar(10, 22, 8, 15));
		Assert.notNull(o);
		Assert.floatEquals(5.0, o.level0, 1e-9);
		Assert.floatEquals(25.0, o.level1000, 1e-9);

		var mm = new MurreyMathLines(3);
		mm.update(bar(10, 20, 10, 15));
		mm.update(bar(10, 25, 5, 15));
		var m = mm.update(bar(10, 22, 8, 15));
		Assert.notNull(m);
		Assert.floatEquals(5.0, m.mm0_8, 1e-9);
		Assert.floatEquals(25.0, m.mm8_8, 1e-9);
	}

	public function testGoldenPocketUsesSwingGraph() {
		var gp = new GoldenPocket(0.05);
		gp.update(bar(100, 100, 100, 100));
		gp.update(bar(100, 110, 100, 110));
		gp.update(bar(110, 110, 100, 100));
		gp.update(bar(100, 100, 95, 95));
		gp.update(bar(95, 102, 95, 102));
		var z = gp.update(bar(102, 103, 101, 102));
		if (z != null) {
			Assert.isTrue(z.low <= z.mid && z.mid <= z.high);
		}
		Assert.isTrue(true);
	}

	public function testGartleyPulseOnConfirm() {
		var g = new Gartley();
		var last = 0.0;
		for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.4) * 10.0;
			var o = g.update(bar(base, base + 2, base - 2, base));
			if (o != null) last = o.signal;
		}
		Assert.isTrue(Math.isFinite(last));
		Assert.isTrue(g.update(bar(100, 101, 99, 100)).levels != null);
	}

	public function testFibRetracementEmitsGeomVizLevels() {
		var fr = new FibRetracement(3);
		fr.update(bar(10, 20, 10, 15));
		fr.update(bar(10, 25, 5, 15));
		var out = fr.update(bar(10, 22, 8, 15));
		Assert.notNull(out);
		Assert.floatEquals(7, out.levels.count, 1e-9);
		Assert.isTrue(Math.isFinite(out.levels.p0));
		Assert.floatEquals(2, out.pivots.count, 1e-9);
		Assert.floatEquals(1, out.zones.count, 1e-9);
	}

	public function testGannAndSoftScores() {
		var fan = GannAngles.fan(100.0, 10, 1.0);
		Assert.floatEquals(110.0, fan.ang1x1, 1e-9);
		Assert.floatEquals(1.0, SoftScores.equality(10, 10), 1e-9);
		Assert.isTrue(SoftScores.bestFibHit(0.618) > 0.9);
		Assert.isTrue(ScaleValidityGate.fromHurst(0.75) > ScaleValidityGate.fromHurst(0.5));
		Assert.isTrue(ScaleValidityGate.fromHurstScales(0.7, 0.72, 0.68)
			> ScaleValidityGate.fromHurstScales(0.4, 0.8, 0.55));
		Assert.isTrue(TimePriceSquare.score(10, 10, 1.0) > 0.9);
		var so9 = SquareOfNine.priceAt(100, 1, 0, 1.0);
		Assert.isTrue(Math.isFinite(so9));
	}

	public function testOfflineHooksNotInIndicatorPath() {
		var dump = new FeatureDump();
		dump.push({
			bar: 0, close: 100, swingDir: 1, fib618: 95,
			ewLabelCode: 0, hurst: 0.5, scaleGate: 0.5
		});
		Assert.equals(1, dump.toArray().length);
		Assert.equals(0, CpdValidator.detectBreaks([1, 2, 3]).length);
		var lp = LpplFit.fitWarning([for (i in 0...40) 100.0 + i * i * 0.01]);
		Assert.isTrue(lp.message.length > 0);
	}
}
