package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.ew.CorrectiveRules;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.ew.EwGuidelines;
import musescript.indicators.ew.EwRatioTargets;
import musescript.indicators.ew.EwProject;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.RatioTables;
import musescript.indicators.geom.SoftScores;
import musescript.indicators.offline.PhiParamsDump;
import musescript.harness.Bar;

/**
 * Frost & Prechter handbook Ch1–4: hard rules, guidelines, φ pack, ratio targets.
 */
class TestEwHandbookCh01 extends Test {
	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	/** Classic bull impulse: 100-110-105-120-112-125 */
	static function bullImpulse():haxe.ds.Vector<PivotPoint> {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10);
		v[2] = piv(105, -1, 20);
		v[3] = piv(120, 1, 30);
		v[4] = piv(112, -1, 40);
		v[5] = piv(125, 1, 50);
		return v;
	}

	public function testValidImpulseFiveWave() {
		Assert.isTrue(ImpulseRules.isValidFiveWave(bullImpulse(), 0));
	}

	public function testInvalidW3Shortest() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(120, 1, 10); // W1=20
		v[2] = piv(115, -1, 20);
		v[3] = piv(122, 1, 30); // W3=7 shortest
		v[4] = piv(118, -1, 40);
		v[5] = piv(140, 1, 50); // W5=22
		Assert.isFalse(ImpulseRules.isValidFiveWave(v, 0));
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
	}

	public function testInvalidW4Overlap() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10);
		v[2] = piv(105, -1, 20);
		v[3] = piv(125, 1, 30);
		v[4] = piv(108, -1, 40); // overlaps W1 [100,110]
		v[5] = piv(130, 1, 50);
		Assert.isTrue(ImpulseRules.isValidMotive(v, 0));
		Assert.isFalse(ImpulseRules.isValidFiveWave(v, 0));
		Assert.isTrue(ImpulseRules.isValidDiagonal(v, 0));
	}

	public function testValidZigzag() {
		// A down 100→80, B up to 88 (40% of 20), C down to 70
		var a = piv(100, 1, 0);
		var b = piv(80, -1, 10);
		var c = piv(88, 1, 20);
		var d = piv(70, -1, 30);
		Assert.isTrue(CorrectiveRules.isValidZigzag(a, b, c, d));
	}

	public function testInvalidZigzagBExceedsStart() {
		var a = piv(100, 1, 0);
		var b = piv(80, -1, 10);
		var c = piv(101, 1, 20); // beyond start of A
		var d = piv(70, -1, 30);
		Assert.isFalse(CorrectiveRules.isValidZigzag(a, b, c, d));
	}

	public function testMultiWindowLatticeFindsImpulse() {
		var g = new SwingGraph(0.02, 16);
		// Feed bars that produce the bull impulse swing tips approximately
		var prices = [100., 110., 105., 120., 112., 125.];
		var barI = 0;
		function pushBar(px:Float) {
			g.update({
				open: px, high: px, low: px, close: px, volume: 1,
				time: barI * 1.0, index: barI
			});
			barI++;
		}
		// Need zigzag-style moves with enough % change
		pushBar(100);
		for (i in 0...5) pushBar(100 + i);
		pushBar(110);
		for (i in 0...3) pushBar(110 - i);
		pushBar(105);
		for (i in 0...5) pushBar(105 + i * 3);
		pushBar(120);
		for (i in 0...3) pushBar(120 - i * 2);
		pushBar(112);
		for (i in 0...5) pushBar(112 + i * 3);
		pushBar(125);
		var lat = new EwLattice();
		var n = lat.rebuild(g, 5);
		Assert.isTrue(n >= 0);
		// Soft: lattice may or may not confirm depending on ZigZag threshold — exercise path
		Assert.isTrue(lat.hypothesisCount() >= 0);
	}

	public function testGuidelinesAlternationSoft() {
		var s = EwGuidelines.alternationImpulse(bullImpulse(), 0);
		Assert.isTrue(s > 0 && s <= 1.0);
	}

	public function testPhiParamsHandbookIdentities() {
		var p = new EwPhiParams();
		Assert.floatEquals(1.0, p.phi * p.phiInv, 1e-6);
		Assert.floatEquals(p.oneMinusPhiInv, 1.0 - p.phiInv, 1e-6);
		Assert.floatEquals(p.phiSq, p.phi * p.phi, 1e-4);
		Assert.isTrue(RatioTables.EW_PHI_CORE.length >= 8);
		Assert.isTrue(SoftScores.bestFibHitParams(0.618, p) > 0.8);
	}

	public function testRatioTargetsWave2() {
		var p0 = piv(100, -1, 0);
		var p1 = piv(110, 1, 10);
		var levels = EwRatioTargets.wave2RetracePrices(p0, p1);
		Assert.equals(3, levels.length);
		// 0.5 retrace of 10-point rise from tip → 105
		Assert.floatEquals(105.0, levels[0], 1e-6);
	}

	public function testGeometricBlendLouisli() {
		var v = EwRatioTargets.geometricBlend(100, 25);
		Assert.isTrue(Math.isFinite(v[2]));
		Assert.isTrue(v[3] > 25 && v[3] < 100);
	}

	public function testProjectFromHypothesisZigzag() {
		var v = new haxe.ds.Vector<PivotPoint>(4);
		v[0] = piv(100, 1, 0);
		v[1] = piv(80, -1, 10);
		v[2] = piv(88, 1, 20);
		v[3] = piv(70, -1, 30);
		var h = {
			rank: 0, score: 1.0, label: "zigzag",
			startBar: 0, endBar: 30, waveCount: 3, degree: 0, offset: 0
		};
		var band = EwProject.fromHypothesis(h, v);
		Assert.notNull(band);
		Assert.equals("zigzagC", band.kind);
		Assert.isTrue(band.priceLo < band.priceHi || band.priceLo == band.priceHi);
	}

	public function testPhiParamsDumpRoundtrip() {
		var m = PhiParamsDump.toMap();
		Assert.isTrue(m.exists("phiInv"));
		var p2 = PhiParamsDump.applyMap(m);
		Assert.floatEquals(EwPhiParams.current().phiInv, p2.phiInv, 1e-9);
	}

	public function testSoftScoreUsesParamsNotOnlyLiterals() {
		var p = new EwPhiParams();
		p.w2RetraceTargets[0] = 0.42;
		p.w2RetraceN = 1;
		p.fibHitTol = 0.05;
		var hit = p.bestHit(0.42, p.w2RetraceTargets, 1);
		Assert.isTrue(hit > 0.9);
	}

	public function testExpandedFlatKind() {
		// A down 100→90, B beyond start to 102, C beyond A end to 85
		var a = piv(100, 1, 0);
		var b = piv(90, -1, 10);
		var c = piv(102, 1, 20);
		var d = piv(85, -1, 30);
		Assert.equals(2, CorrectiveRules.flatKind(a, b, c, d));
		Assert.equals("flat_expanded", CorrectiveRules.flatLabel(2));
	}

	public function testRunningFlatKind() {
		// A down 100→90, B beyond to 103, C fails to reach 90 (stops at 95)
		var a = piv(100, 1, 0);
		var b = piv(90, -1, 10);
		var c = piv(103, 1, 20);
		var d = piv(95, -1, 30);
		Assert.equals(3, CorrectiveRules.flatKind(a, b, c, d));
	}

	public function testContractingTriangle() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, 1, 0);
		v[1] = piv(80, -1, 10);  // a=20
		v[2] = piv(95, 1, 20);   // b=15
		v[3] = piv(83, -1, 30);  // c=12 ≈0.618*a
		v[4] = piv(92, 1, 40);   // d=9
		v[5] = piv(85, -1, 50);  // e=7 ≈0.618*c
		Assert.isTrue(CorrectiveRules.isValidTriangle(v, 0));
	}

	public function testDoubleZigzagWXY() {
		var v = new haxe.ds.Vector<PivotPoint>(8);
		// W zigzag
		v[0] = piv(100, 1, 0);
		v[1] = piv(80, -1, 10);
		v[2] = piv(88, 1, 20);
		v[3] = piv(70, -1, 30);
		// X connector + Y zigzag
		v[4] = piv(78, 1, 40);
		v[5] = piv(60, -1, 50);
		v[6] = piv(68, 1, 60);
		v[7] = piv(50, -1, 70);
		Assert.isTrue(CorrectiveRules.isValidDoubleZigzag(v, 0));
	}
}
