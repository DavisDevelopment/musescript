package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.ew.CorrectiveRules;
import musescript.indicators.ew.EwHypothesis;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.ew.EwProject;
import musescript.indicators.ew.EwRatioTargets;
import musescript.indicators.ew.EwInvalidation;

/**
 * Section A pattern expansion: flats soft-by-kind, WXZ, triangles,
 * ending/leading diagonals, truncated fifth, extension labels + projection.
 */
class TestEwHandbookPatternsA extends Test {
	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	static function hyp(label:String, offset:Int, waveCount:Int, endBar:Int):EwHypothesis {
		return {
			rank: 0, score: 1.0, label: label,
			startBar: 0, endBar: endBar, waveCount: waveCount, degree: 0, offset: offset,
			parentHypothesisId: -1, parentStartBar: -1, parentEndBar: -1, nestScore: 1.0,
			invalidatePrice: Math.NaN, invalidateBar: Math.NaN
		};
	}

	/** Classic bull impulse: 100-110-105-120-112-125 → W3 extended. */
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

	public function testTruncatedFifthDetection() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10);
		v[2] = piv(105, -1, 20);
		v[3] = piv(120, 1, 30);
		v[4] = piv(112, -1, 40);
		v[5] = piv(118, 1, 50); // fails beyond W3 tip 120
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));
		Assert.isTrue(ImpulseRules.isTruncatedFifth(v, 0));
		Assert.equals("impulse5_trunc", ImpulseRules.impulseLabel(v, 0));
	}

	public function testExtensionWhichExt3() {
		Assert.equals(3, ImpulseRules.extensionWhich(bullImpulse(), 0));
		Assert.equals("impulse5_ext3", ImpulseRules.impulseLabel(bullImpulse(), 0));
	}

	public function testExtensionWhichExt1() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(130, 1, 10); // W1=30
		v[2] = piv(120, -1, 20);
		v[3] = piv(145, 1, 30); // W3=25
		v[4] = piv(135, -1, 40); // outside W1 [100,130]
		v[5] = piv(155, 1, 50); // W5=20
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));
		Assert.equals(1, ImpulseRules.extensionWhich(v, 0));
		Assert.equals("impulse5_ext1", ImpulseRules.impulseLabel(v, 0));
	}

	public function testExtensionWhichExt5() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10); // W1=10
		v[2] = piv(105, -1, 20);
		v[3] = piv(118, 1, 30); // W3=13
		v[4] = piv(112, -1, 40);
		v[5] = piv(140, 1, 50); // W5=28
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));
		Assert.equals(5, ImpulseRules.extensionWhich(v, 0));
		Assert.equals("impulse5_ext5", ImpulseRules.impulseLabel(v, 0));
	}

	public function testDiagonalEndingVsLeading() {
		// Ending: contracting wedge + W4/W1 overlap
		var ending = new haxe.ds.Vector<PivotPoint>(6);
		ending[0] = piv(100, -1, 0);
		ending[1] = piv(120, 1, 10);
		ending[2] = piv(110, -1, 20);
		ending[3] = piv(130, 1, 30);
		ending[4] = piv(115, -1, 40); // overlaps W1 [100,120]
		ending[5] = piv(125, 1, 50);
		Assert.equals(1, ImpulseRules.diagonalKind(ending, 0));
		Assert.equals("diagonal_ending", ImpulseRules.diagonalLabel(1));

		// Leading: expanding actionaries + overlap
		var leading = new haxe.ds.Vector<PivotPoint>(6);
		leading[0] = piv(100, -1, 0);
		leading[1] = piv(120, 1, 10);
		leading[2] = piv(110, -1, 20);
		leading[3] = piv(135, 1, 30);
		leading[4] = piv(115, -1, 40);
		leading[5] = piv(145, 1, 50);
		Assert.equals(2, ImpulseRules.diagonalKind(leading, 0));
		Assert.equals("diagonal_leading", ImpulseRules.diagonalLabel(2));
	}

	public function testExpandingTriangle() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, 1, 0);
		v[1] = piv(90, -1, 10);  // a=10
		v[2] = piv(96, 1, 20);   // b=6
		v[3] = piv(84, -1, 30);  // c=12
		v[4] = piv(100, 1, 40);  // d=16
		v[5] = piv(70, -1, 50);  // e=30
		Assert.equals(2, CorrectiveRules.triangleKind(v, 0, 0));
		Assert.equals("triangle_expanding", CorrectiveRules.triangleLabel(2));
	}

	public function testTriangleDegreeStricterAtCoarse() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, 1, 0);
		v[1] = piv(80, -1, 10);
		v[2] = piv(95, 1, 20);
		v[3] = piv(83, -1, 30);
		v[4] = piv(92, 1, 40);
		v[5] = piv(85, -1, 50);
		Assert.equals(1, CorrectiveRules.triangleKind(v, 0, 0));
		// Same structure should still pass degree 1 (clear convergence)
		Assert.equals(1, CorrectiveRules.triangleKind(v, 0, 1));
	}

	public function testDoubleThreeWxZ() {
		var v = new haxe.ds.Vector<PivotPoint>(8);
		// W zigzag
		v[0] = piv(100, 1, 0);
		v[1] = piv(80, -1, 10);
		v[2] = piv(88, 1, 20);
		v[3] = piv(70, -1, 30);
		// X + Z expanded flat (not zigzag — B beyond start of A)
		v[4] = piv(78, 1, 40);
		v[5] = piv(68, -1, 50);
		v[6] = piv(80, 1, 60);
		v[7] = piv(60, -1, 70);
		Assert.isFalse(CorrectiveRules.isValidDoubleZigzag(v, 0));
		Assert.equals(1, CorrectiveRules.wxzKind(v, 0));
		Assert.isTrue(CorrectiveRules.isValidDoubleThree(v, 0));
	}

	public function testFlatSoftScoreExpandedVsRunning() {
		var a = piv(100, 1, 0);
		var b = piv(90, -1, 10);
		var cExp = piv(102, 1, 20);
		var dExp = piv(85, -1, 30);
		var cRun = piv(103, 1, 20);
		var dRun = piv(95, -1, 30);
		var sExp = CorrectiveRules.softScoreFlat(a, b, cExp, dExp, 2);
		var sRun = CorrectiveRules.softScoreFlat(a, b, cRun, dRun, 3);
		Assert.isTrue(sExp > 0 && sRun > 0);
		Assert.isTrue(Math.isFinite(sExp) && Math.isFinite(sRun));
	}

	public function testTruncationProjectionCautious() {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10);
		v[2] = piv(105, -1, 20);
		v[3] = piv(120, 1, 30);
		v[4] = piv(112, -1, 40);
		v[5] = piv(118, 1, 50);
		var trunc = hyp("impulse5_trunc", 0, 5, 50);
		var bTrunc = EwProject.fromHypothesis(trunc, v);
		Assert.notNull(bTrunc);
		Assert.equals("impulseW5_trunc", bTrunc.kind);
		var mid = (bTrunc.priceLo + bTrunc.priceHi) * 0.5;
		// Cautious: band pulled toward W3 tip (120) vs chasing W5 tip (118) or far extensions
		Assert.isTrue(Math.abs(mid - 120.0) < 8.0);
		var full = EwRatioTargets.wave5Targets(v[0], v[1], v[4]);
		var flo = full[0];
		var fhi = full[0];
		for (i in 1...full.length) {
			if (full[i] < flo) flo = full[i];
			if (full[i] > fhi) fhi = full[i];
		}
		Assert.isTrue((bTrunc.priceHi - bTrunc.priceLo) < (fhi - flo) + 1e-9);
	}

	public function testExtensionAwareW5Targets() {
		var p0 = piv(100, -1, 0);
		var p1 = piv(110, 1, 10);
		var p4 = piv(112, -1, 40);
		var base = EwRatioTargets.wave5Targets(p0, p1, p4);
		var ext3 = EwRatioTargets.wave5TargetsExt(p0, p1, p4, 3);
		var ext5 = EwRatioTargets.wave5TargetsExt(p0, p1, p4, 5);
		Assert.equals(base.length, ext3.length);
		// Ext-5 stretch pushes farthest target beyond base farthest
		var baseMax = base[0];
		var ext5Max = ext5[0];
		for (i in 1...base.length) {
			if (base[i] > baseMax) baseMax = base[i];
			if (ext5[i] > ext5Max) ext5Max = ext5[i];
		}
		Assert.isTrue(ext5Max >= baseMax - 1e-9);
		// Ext-3 first target nearer (0.618 of W1 from p4)
		Assert.floatEquals(112 + 10 * 0.6180339887, ext3[0], 1e-4);
	}

	public function testInvalidationCoversNewLabels() {
		var v = bullImpulse();
		Assert.floatEquals(100.0, EwInvalidation.forLabel("impulse5_ext3", v, 0).price, 1e-9);
		Assert.floatEquals(100.0, EwInvalidation.forLabel("impulse5_trunc", v, 0).price, 1e-9);
		Assert.floatEquals(100.0, EwInvalidation.forLabel("diagonal_ending", v, 0).price, 1e-9);
	}

	public function testImpulseFamilyHelpers() {
		Assert.isTrue(ImpulseRules.isImpulseFamily("impulse5_ext3"));
		Assert.isTrue(ImpulseRules.isDiagonalFamily("diagonal_leading"));
		Assert.isFalse(ImpulseRules.isImpulseFamily("zigzag"));
	}
}
