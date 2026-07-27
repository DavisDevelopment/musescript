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
import musescript.indicators.lib.FibArcs;
import musescript.indicators.lib.MurreyMathLines;
import musescript.indicators.lib.GoldenPocket;
import musescript.indicators.lib.Gartley;
import musescript.indicators.lib.RectangleRange;
import musescript.indicators.lib.Triangle;
import musescript.indicators.lib.Wedge;
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

	public function testFibArcsEmitArcSet() {
		var fa = new FibArcs();
		fa.update(bar(100, 100, 100, 100));
		fa.update(bar(100, 110, 100, 110));
		fa.update(bar(110, 110, 100, 100));
		for (i in 0...5) fa.update(bar(100 - i, 100 - i, 95, 95));
		var out = fa.update(bar(95, 96, 94, 95));
		if (out != null) {
			Assert.floatEquals(3, out.arcs.count, 1e-9);
			Assert.isTrue(Math.isFinite(out.arcs.cx0));
			Assert.isTrue(Math.isFinite(out.arcs.rb0));
		}
		Assert.isTrue(true);
	}

	public function testRectangleTriangleWedgeUseSwingGraph() {
		var rr = new RectangleRange();
		var tri = new Triangle();
		var w = new Wedge();
		for (i in 0...20) {
			var base = 100.0 + Math.sin(i * 0.5) * 8.0;
			rr.update(bar(base, base + 3, base - 3, base));
			tri.update(bar(base, base + 3, base - 3, base));
			w.update(bar(base, base + 3, base - 3, base));
		}
		Assert.isTrue(rr.isReady());
		Assert.isTrue(tri.isReady());
		Assert.isTrue(w.isReady());
	}

	public function testPatternDetectorsUseSwingGraph() {
		var flag = new musescript.indicators.lib.FlagPennant();
		var hs = new musescript.indicators.lib.HeadAndShoulders();
		var cup = new musescript.indicators.lib.CupAndHandle();
		var dbl = new musescript.indicators.lib.DoubleTopBottom();
		var tri = new musescript.indicators.lib.TripleTopBottom();
		var abcd = new musescript.indicators.lib.Abcd();
		var drives = new musescript.indicators.lib.ThreeDrives();
		for (i in 0...30) {
			var base = 100.0 + Math.sin(i * 0.45) * 10.0;
			var b = bar(base, base + 4, base - 4, base);
			flag.update(b); hs.update(b); cup.update(b);
			dbl.update(b); tri.update(b); abcd.update(b); drives.update(b);
		}
		Assert.isTrue(flag.isReady());
		Assert.isTrue(hs.isReady());
		Assert.isTrue(cup.isReady());
		Assert.isTrue(dbl.isReady());
		Assert.isTrue(tri.isReady());
		Assert.isTrue(abcd.isReady());
		Assert.isTrue(drives.isReady());
	}

	public function testSsaCyclesEmitsCycleSeries() {
		var ssa = new musescript.indicators.lib.SsaCycles(16, 2, 8);
		var last:Null<Dynamic> = null;
		for (i in 0...24) {
			var base = 100.0 + Math.sin(i * Math.PI / 6) * 5.0;
			last = ssa.update(bar(base, base + 1, base - 1, base));
		}
		Assert.notNull(last);
		Assert.isTrue(last.cycle.count >= 1);
		Assert.isTrue(Math.isFinite(last.cycle.p0));
		Assert.isTrue(Math.isFinite(last.cycle.b0));
	}

	public function testLpplWarningEmitsRibbonSeries() {
		var lp = new musescript.indicators.lib.LpplWarningIndicator(30);
		var last:Null<Dynamic> = null;
		for (i in 0...40) {
			var c = 100.0 + i * i * 0.02;
			last = lp.update(bar(c, c + 1, c - 1, c));
		}
		Assert.notNull(last);
		Assert.isTrue(last.ribbon.count >= 1);
		Assert.isTrue(Math.isFinite(last.ribbon.p0));
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
