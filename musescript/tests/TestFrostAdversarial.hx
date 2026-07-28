package musescript.tests;

import utest.Assert;
import utest.Test;
import haxe.ds.Vector;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.ew.CorrectiveRules;
import musescript.indicators.ew.EwGuidelines;

/**
 * Bucket E4 — Frost & Prechter adversarial pivot battery.
 * Hard rules must reject known-invalid skeletons; soft guidelines stay in [0,1] and never hard-gate.
 */
class TestFrostAdversarial extends Test {
	static function piv(price:Float, dir:Float, bar:Int):PivotPoint
		return new PivotPoint(price, dir, bar);

	/** Classic valid bull impulse: 100-110-105-120-112-125 */
	static function bullOk():Vector<PivotPoint> {
		var v = new Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 10);
		v[2] = piv(105, -1, 20);
		v[3] = piv(120, 1, 30);
		v[4] = piv(112, -1, 40);
		v[5] = piv(125, 1, 50);
		return v;
	}

	/** Mirror bear impulse. */
	static function bearOk():Vector<PivotPoint> {
		var v = new Vector<PivotPoint>(6);
		v[0] = piv(125, 1, 0);
		v[1] = piv(115, -1, 10);
		v[2] = piv(120, 1, 20);
		v[3] = piv(105, -1, 30);
		v[4] = piv(113, 1, 40);
		v[5] = piv(100, -1, 50);
		return v;
	}

	static function copy(src:Vector<PivotPoint>):Vector<PivotPoint> {
		var v = new Vector<PivotPoint>(src.length);
		for (i in 0...src.length) v[i] = src[i].copy();
		return v;
	}

	public function testValidBullAndBearPass() {
		Assert.isTrue(ImpulseRules.isValidFiveWave(bullOk(), 0));
		Assert.isTrue(ImpulseRules.isValidMotive(bullOk(), 0));
		Assert.isTrue(ImpulseRules.isValidFiveWave(bearOk(), 0));
	}

	public function testAdversarialW2ExceedsW1() {
		var v = copy(bullOk());
		v[2] = piv(99, -1, 20); // W2 depth > W1
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
		Assert.isFalse(ImpulseRules.isValidFiveWave(v, 0));
	}

	public function testAdversarialW4ExceedsW3() {
		var v = copy(bullOk());
		v[4] = piv(100, -1, 40); // W4 length > W3
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
	}

	public function testAdversarialW3FailsBeyondW1() {
		var v = copy(bullOk());
		v[3] = piv(109, 1, 30); // W3 tip not beyond W1 tip 110
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
	}

	public function testAdversarialW3Shortest() {
		var v = new Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(120, 1, 10); // W1=20
		v[2] = piv(115, -1, 20);
		v[3] = piv(122, 1, 30); // W3=7 shortest
		v[4] = piv(118, -1, 40);
		v[5] = piv(140, 1, 50); // W5=22
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
	}

	public function testAdversarialNonAlternating() {
		var v = copy(bullOk());
		v[2] = piv(105, 1, 20); // same direction as W1 tip — breaks alternation
		Assert.isFalse(ImpulseRules.isValidMotive(v, 0));
	}

	public function testAdversarialW4OverlapIsDiagonalNotImpulse() {
		var v = copy(bullOk());
		v[4] = piv(108, -1, 40); // inside W1 [100,110]
		Assert.isTrue(ImpulseRules.wave4OverlapsWave1(v, 0));
		Assert.isTrue(ImpulseRules.isValidMotive(v, 0));
		Assert.isFalse(ImpulseRules.isValidFiveWave(v, 0));
		Assert.isTrue(ImpulseRules.isValidDiagonal(v, 0));
	}

	public function testAdversarialTruncatedFifthStillImpulse() {
		var v = copy(bullOk());
		v[5] = piv(118, 1, 50); // fails beyond W3 tip 120
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));
		Assert.isTrue(ImpulseRules.isTruncatedFifth(v, 0));
	}

	public function testZigzagAdversarialBBeyondA() {
		var a = piv(100, 1, 0);
		var b = piv(80, -1, 10);
		var c = piv(101, 1, 20);
		var d = piv(70, -1, 30);
		Assert.isFalse(CorrectiveRules.isValidZigzag(a, b, c, d));
	}

	public function testZigzagValidFixture() {
		var a = piv(100, 1, 0);
		var b = piv(80, -1, 10);
		var c = piv(88, 1, 20);
		var d = piv(70, -1, 30);
		Assert.isTrue(CorrectiveRules.isValidZigzag(a, b, c, d));
	}

	public function testFlatExpandedVsRunningKinds() {
		// Expanded: B beyond start of A, C beyond end of A (down A)
		var p0 = piv(100, 1, 0);
		var p1 = piv(80, -1, 10);  // A down 20
		var p2 = piv(105, 1, 20);  // B beyond start
		var p3 = piv(70, -1, 30);  // C beyond A end
		Assert.equals(2, CorrectiveRules.flatKind(p0, p1, p2, p3));

		// Running: B beyond, C short of A end
		var r3 = piv(85, -1, 30);
		Assert.equals(3, CorrectiveRules.flatKind(p0, p1, p2, r3));
	}

	public function testGuidelinesSoftNeverHardReject() {
		var short = new Vector<PivotPoint>(3);
		for (i in 0...3) short[i] = piv(100 + i, i % 2 == 0 ? 1.0 : -1.0, i);
		Assert.floatEquals(0.5, EwGuidelines.alternationImpulse(short, 0));
		var s = EwGuidelines.scoreImpulse(bullOk(), 0);
		Assert.isTrue(s >= 0 && s <= 1, 'guideline score=$s');
	}

	public function testAdversarialBatteryAllReject() {
		var ok = bullOk();
		Assert.isTrue(ImpulseRules.isValidFiveWave(ok, 0));
		var cases:Array<{name:String, v:Vector<PivotPoint>}> = [];
		function add(name:String, mut:Vector<PivotPoint>->Void) {
			var v = copy(ok);
			mut(v);
			cases.push({ name: name, v: v });
		}
		add("w2_gt_w1", function(v) v[2] = piv(98, -1, 20));
		add("w4_gt_w3", function(v) v[4] = piv(100, -1, 40));
		add("w3_not_beyond", function(v) v[3] = piv(109, 1, 30));
		add("non_alt", function(v) v[2] = piv(105, 1, 20));
		add("zero_w1", function(v) { v[0] = piv(110, -1, 0); v[1] = piv(110, 1, 10); });
		add("bear_w2_gt", function(v) {
			var b = bearOk();
			for (i in 0...6) v[i] = b[i];
			v[2] = piv(130, 1, 20);
		});
		for (c in cases) {
			Assert.isFalse(ImpulseRules.isValidFiveWave(c.v, 0), c.name + " must reject");
		}
	}
}
