package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SoftScores;

/**
 * Hard corrective rules — Frost & Prechter Ch1 (Lessons 6–9).
 * Soft Fib/time use EwPhiParams.
 *
 * Labels: zigzag | flat | flat_expanded | flat_running
 *         triangle | triangle_expanding
 *         double_zigzag | double_three (W-X-Z mixed corrective)
 */
class CorrectiveRules {
	/**
	 * Zigzag price skeleton over four pivots (0=start A, 1=A end, 2=B end, 3=C end).
	 * Sharp: B does not exceed start of A; B retraces A in param band; C >= zigzagCMinVsA of A.
	 */
	public static function isValidZigzag(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):Bool {
		var p = params != null ? params : EwPhiParams.current();
		if (p0.direction == p1.direction) return false;
		if (p1.direction == p2.direction) return false;
		if (p2.direction == p3.direction) return false;
		var ab = Math.abs(p1.price - p0.price);
		var bc = Math.abs(p2.price - p1.price);
		var cd = Math.abs(p3.price - p2.price);
		if (ab <= 0) return false;
		var retrace = bc / ab;
		if (retrace < p.zigzagBMin || retrace > p.zigzagBMax) return false;
		var upA = p1.price > p0.price;
		if (upA) {
			if (p2.price <= p0.price + 1e-12) return false;
		} else {
			if (p2.price >= p0.price - 1e-12) return false;
		}
		if (cd / ab < p.zigzagCMinVsA) return false;
		return true;
	}

	/**
	 * Flat subtype for A-B-C (3-3-5 price skeleton).
	 * @return 0=none, 1=regular, 2=expanded, 3=running
	 */
	public static function flatKind(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):Int {
		var p = params != null ? params : EwPhiParams.current();
		if (p0.direction == p1.direction) return 0;
		if (p1.direction == p2.direction) return 0;
		if (p2.direction == p3.direction) return 0;
		var ab = Math.abs(p1.price - p0.price);
		if (!(ab > 0)) return 0;
		var upA = p1.price > p0.price;
		// B relative to start of A (p0)
		var bBeyondStart = upA ? (p2.price < p0.price - p.flatBBeyond * ab)
			: (p2.price > p0.price + p.flatBBeyond * ab);
		var bNearStart = Math.abs(p2.price - p0.price) / ab <= 0.25;
		// C relative to end of A (p1)
		var cBeyondA = upA ? (p3.price > p1.price + 1e-12) : (p3.price < p1.price - 1e-12);
		var cShortOfA = upA ? (p3.price < p1.price - 1e-12) : (p3.price > p1.price + 1e-12);
		var cNearA = Math.abs(p3.price - p1.price) / ab <= 0.35;
		var cLen = Math.abs(p3.price - p2.price) / ab;
		if (cLen < 0.5) return 0;

		// Expanded: B beyond start of A, C beyond end of A
		if (bBeyondStart && cBeyondA) return 2;
		// Running: B beyond start of A, C fails to reach end of A
		if (bBeyondStart && cShortOfA) return 3;
		// Regular: B near start of A, C near/slightly beyond end of A
		if ((bNearStart || !bBeyondStart) && (cNearA || cBeyondA)) return 1;
		return 0;
	}

	public static function isValidFlat(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):Bool {
		return flatKind(p0, p1, p2, p3, params) != 0;
	}

	public static function flatLabel(kind:Int):String {
		return switch (kind) {
			case 1: "flat";
			case 2: "flat_expanded";
			case 3: "flat_running";
			default: "unknown";
		};
	}

	/**
	 * Triangle kind over six pivots (start + five tips a–e).
	 * Degree-aware: higher relative degree requires clearer boundary convergence/divergence.
	 * @return 0=none, 1=contracting, 2=expanding
	 */
	public static function triangleKind(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, degree:Int = 0, ?params:EwPhiParams):Int {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0;
		for (i in 0...5) {
			if (pivots[offset + i].direction == pivots[offset + i + 1].direction) return 0;
		}
		var len = new haxe.ds.Vector<Float>(5);
		for (i in 0...5) {
			len[i] = Math.abs(pivots[offset + i + 1].price - pivots[offset + i].price);
			if (!(len[i] > 0)) return 0;
		}

		// Degree-aware boundary strictness (hard floor, not learnable):
		// degree 0 → mild; degree≥1 → clearer extreme convergence/divergence.
		var edgeTol = degree >= 1 ? 0.92 : 0.98;
		var shrinkFloor = degree >= 1 ? 0.90 : 0.95;

		var span0 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var spanE = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(span0 > 0)) return 0;

		// Odd-wave extremes (a,c,e tips = offset+1,+3,+5) and even (b,d = +2,+4)
		var aTip = pivots[offset + 1].price;
		var cTip = pivots[offset + 3].price;
		var eTip = pivots[offset + 5].price;
		var bTip = pivots[offset + 2].price;
		var dTip = pivots[offset + 4].price;
		var upA = aTip > pivots[offset].price;

		// Contracting: e < c <~ a on actionaries; boundary span shrinks; extremes converge
		var contractingLens = len[4] < len[0] * shrinkFloor && len[2] < len[0] * 1.05 && len[4] <= len[2] * 1.05;
		var contractingSpan = spanE < span0 * edgeTol;
		var convergingOdds = upA
			? (eTip >= cTip - 1e-12 && cTip >= aTip - Math.abs(aTip) * 1e-9) // downward tips rise toward midline
			: (eTip <= cTip + 1e-12 && cTip <= aTip + Math.abs(aTip) * 1e-9);
		// Softer odd-wave convergence: |e-c| and |c-a| shrinking along the trendline
		var oddSpread0 = Math.abs(cTip - aTip);
		var oddSpread1 = Math.abs(eTip - cTip);
		var oddConverge = oddSpread1 <= oddSpread0 * edgeTol + 1e-12;
		var evenSpread0 = Math.abs(dTip - bTip);
		// For contracting, even extremes should also tighten vs first corrective span
		var evenConverge = evenSpread0 <= Math.abs(bTip - pivots[offset].price) * 1.5 + 1e-12;

		if (contractingLens && contractingSpan && (oddConverge || convergingOdds) && evenConverge) {
			var eOverC = len[4] / len[2];
			var cOverA = len[2] / len[0];
			var hit = SoftScores.fibRatio(eOverC, p.phiInv, p.fibHitTol + 0.08)
				+ SoftScores.fibRatio(cOverA, p.phiInv, p.fibHitTol + 0.08)
				+ SoftScores.fibRatio(eOverC, 1.0, 0.2);
			if (hit > 0.35) return 1;
		}

		// Expanding: e > c >~ a; boundary span grows
		var expandingLens = len[4] > len[0] * (2.0 - shrinkFloor) && len[2] >= len[0] * 0.95 && len[4] >= len[2] * 0.95;
		var expandingSpan = spanE > span0 * (2.0 - edgeTol);
		var oddDiverge = oddSpread1 >= oddSpread0 * (2.0 - edgeTol) - 1e-12;
		if (expandingLens && expandingSpan && oddDiverge) {
			return 2;
		}
		return 0;
	}

	/**
	 * Contracting triangle a-b-c-d-e over six pivots (start + five tips).
	 * Prefer triangleKind; this keeps the prior boolean API.
	 */
	public static function isValidTriangle(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Bool {
		return triangleKind(pivots, offset, 0, params) != 0;
	}

	public static function isValidTriangleAtDegree(pivots:haxe.ds.Vector<PivotPoint>, offset:Int, degree:Int, ?params:EwPhiParams):Bool {
		return triangleKind(pivots, offset, degree, params) != 0;
	}

	public static function triangleLabel(kind:Int):String {
		return switch (kind) {
			case 1: "triangle";
			case 2: "triangle_expanding";
			default: "unknown";
		};
	}

	/** @deprecated use isValidTriangle */
	public static function isValidTriangleStub(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		return isValidTriangle(pivots, offset);
	}

	/**
	 * Double zigzag W-X-Y over eight pivots (0..7):
	 * W = pivots[o..o+3], X connects o+3 to o+4, Y = pivots[o+4..o+7] as zigzag.
	 */
	public static function isValidDoubleZigzag(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Bool {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 7 >= pivots.length) return false;
		if (!isValidZigzag(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], p))
			return false;
		if (!isValidZigzag(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], p))
			return false;
		var wEnd = pivots[offset + 3];
		var yStart = pivots[offset + 4];
		if (wEnd.direction == yStart.direction) return false;
		var wNet = Math.abs(pivots[offset + 3].price - pivots[offset].price);
		var yNet = Math.abs(pivots[offset + 7].price - pivots[offset + 4].price);
		var xLen = Math.abs(yStart.price - wEnd.price);
		if (!(wNet > 0 && yNet > 0)) return false;
		if (xLen > wNet * 1.2 || xLen > yNet * 1.2) return false;
		return true;
	}

	/**
	 * Double three / W-X-Z: first corrective zigzag, second a flat (or reverse).
	 * Distinct from double zigzag (both zigzags). Eight pivots.
	 * @return 0=none, 1=zigzag+flat (W-X-Z), 2=flat+zigzag (W-X-Z)
	 */
	public static function wxzKind(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Int {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 7 >= pivots.length) return 0;
		var wEnd = pivots[offset + 3];
		var zStart = pivots[offset + 4];
		if (wEnd.direction == zStart.direction) return 0;
		var wNet = Math.abs(pivots[offset + 3].price - pivots[offset].price);
		var zNet = Math.abs(pivots[offset + 7].price - pivots[offset + 4].price);
		var xLen = Math.abs(zStart.price - wEnd.price);
		if (!(wNet > 0 && zNet > 0)) return 0;
		if (xLen > wNet * 1.35 || xLen > zNet * 1.35) return 0;

		var wZig = isValidZigzag(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], p);
		var zFlat = flatKind(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], p) != 0;
		if (wZig && zFlat) return 1;

		var wFlat = flatKind(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], p) != 0;
		var zZig = isValidZigzag(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], p);
		if (wFlat && zZig) return 2;
		return 0;
	}

	public static function isValidDoubleThree(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Bool {
		return wxzKind(pivots, offset, params) != 0;
	}

	public static function softScore(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		var ab = Math.abs(p1.price - p0.price);
		if (!(ab > 0)) return 0.5;
		var bc = Math.abs(p2.price - p1.price);
		var cd = Math.abs(p3.price - p2.price);
		var bHit = p.bestHit(bc / ab, p.zigBTargets, p.zigBTargetsN);
		var cHit = p.bestHit(cd / ab, p.zigCTargets, p.zigCTargetsN);
		var tAB = p1.bar - p0.bar;
		var tBC = p2.bar - p1.bar;
		var tCD = p3.bar - p2.bar;
		var timeSoft = SoftScores.combine(
			SoftScores.timeEquality(tAB, tCD, p.timeHitTol),
			p.bestHit(tBC > 0 ? (tAB * 1.0) / tBC : 1.0, p.timeMultipleTargets, p.timeMultipleN)
		);
		return SoftScores.combine(bHit, cHit, timeSoft);
	}

	/** Flat soft score biased by subtype (expanded C≈1.618A, running softer). */
	public static function softScoreFlat(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, kind:Int, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		var base = softScore(p0, p1, p2, p3, p);
		var ab = Math.abs(p1.price - p0.price);
		if (!(ab > 0)) return base;
		var cRatio = Math.abs(p3.price - p2.price) / ab;
		var bNear = SoftScores.fibRatio(Math.abs(p2.price - p0.price) / ab, p.flatBNear, p.fibHitTol);
		return switch (kind) {
			case 2: SoftScores.combine(base, SoftScores.fibRatio(cRatio, p.phiExt1618, p.fibHitTol), bNear);
			case 3: SoftScores.combine(base * 0.9, SoftScores.fibRatio(cRatio, p.phiInv, p.fibHitTol + 0.1));
			case 1: SoftScores.combine(base, SoftScores.fibRatio(cRatio, p.flatCVsA, p.fibHitTol), bNear);
			default: base;
		};
	}

	public static function softScoreDoubleZigzag(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var a = softScore(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], params);
		var b = softScore(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], params);
		var wNet = Math.abs(pivots[offset + 3].price - pivots[offset].price);
		var yNet = Math.abs(pivots[offset + 7].price - pivots[offset + 4].price);
		var eq = SoftScores.equality(wNet, yNet, 0.25);
		return SoftScores.combine(a, b, eq);
	}

	public static function softScoreDoubleThree(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var kind = wxzKind(pivots, offset, params);
		if (kind == 0) return 0.5;
		var a:Float;
		var b:Float;
		if (kind == 1) {
			a = softScore(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], params);
			var fk = flatKind(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], params);
			b = softScoreFlat(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], fk, params);
		} else {
			var fk = flatKind(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], params);
			a = softScoreFlat(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], fk, params);
			b = softScore(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], params);
		}
		return SoftScores.combine(a, b) * 0.92;
	}

	public static function softScoreTriangle(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0.5;
		var a = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var c = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
		var e = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(a > 0 && c > 0)) return 0.5;
		var kind = triangleKind(pivots, offset, 0, p);
		if (kind == 2) {
			return SoftScores.combine(
				SoftScores.fibRatio(c / a, p.phi, p.fibHitTol + 0.1),
				SoftScores.fibRatio(e / c, p.phi, p.fibHitTol + 0.1)
			);
		}
		return SoftScores.combine(
			SoftScores.fibRatio(c / a, p.phiInv, p.fibHitTol),
			SoftScores.fibRatio(e / c, p.phiInv, p.fibHitTol)
		);
	}

	public static function projectC(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ratio:Float = 1.0):Float {
		return RatioEngine.projectLeg(p0.price, p1.price, p2.price, ratio);
	}
}
