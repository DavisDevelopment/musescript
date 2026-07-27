package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SoftScores;

/**
 * Hard corrective rules — Frost & Prechter Ch1 (Lessons 6–9).
 * Soft Fib/time use EwPhiParams.
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
	 * Contracting triangle a-b-c-d-e over six pivots (start + five tips).
	 * Alternating directions; each successive actionary span tends to shrink;
	 * at least one alternate-wave pair near φ (e≈0.618c or c≈0.618a).
	 */
	public static function isValidTriangle(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Bool {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return false;
		for (i in 0...5) {
			if (pivots[offset + i].direction == pivots[offset + i + 1].direction) return false;
		}
		var len = new haxe.ds.Vector<Float>(5);
		for (i in 0...5) {
			len[i] = Math.abs(pivots[offset + i + 1].price - pivots[offset + i].price);
			if (!(len[i] > 0)) return false;
		}
		// Contracting: e < c < a (or at least e < a and c < a)
		if (!(len[4] < len[0] * 0.95 && len[2] < len[0] * 1.05)) return false;
		if (!(len[4] <= len[2] * 1.05)) return false;
		// Boundary convergence proxy: net range of last two tips vs first two
		var span0 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var spanE = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (spanE > span0 * 0.98) return false;
		// φ alternate relation soft-as-hard band
		var eOverC = len[4] / len[2];
		var cOverA = len[2] / len[0];
		var hit = SoftScores.fibRatio(eOverC, p.phiInv, p.fibHitTol + 0.08)
			+ SoftScores.fibRatio(cOverA, p.phiInv, p.fibHitTol + 0.08)
			+ SoftScores.fibRatio(eOverC, 1.0, 0.2);
		return hit > 0.35;
	}

	/** @deprecated use isValidTriangle */
	public static function isValidTriangleStub(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		return isValidTriangle(pivots, offset);
	}

	/**
	 * Double zigzag W-X-Y over eight pivots (0..7): W=zigzag(0..3), X=leg(3..4 tip via 3,4,5?),
	 * Simpler: W = pivots[o..o+3], X connects o+3 to o+4, Y = pivots[o+4..o+7] as zigzag.
	 * X must be a three-ish corrective connector (here: single opposing leg between W and Y).
	 */
	public static function isValidDoubleZigzag(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Bool {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 7 >= pivots.length) return false;
		if (!isValidZigzag(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], p))
			return false;
		if (!isValidZigzag(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], p))
			return false;
		// X: connecting leg from end of W (p3) to start of Y (p4) — must reverse vs W's C direction
		var wEnd = pivots[offset + 3];
		var yStart = pivots[offset + 4];
		if (wEnd.direction == yStart.direction) return false;
		var wNet = Math.abs(pivots[offset + 3].price - pivots[offset].price);
		var yNet = Math.abs(pivots[offset + 7].price - pivots[offset + 4].price);
		var xLen = Math.abs(yStart.price - wEnd.price);
		if (!(wNet > 0 && yNet > 0)) return false;
		// X typically smaller than W/Y nets
		if (xLen > wNet * 1.2 || xLen > yNet * 1.2) return false;
		return true;
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

	public static function softScoreDoubleZigzag(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var a = softScore(pivots[offset], pivots[offset + 1], pivots[offset + 2], pivots[offset + 3], params);
		var b = softScore(pivots[offset + 4], pivots[offset + 5], pivots[offset + 6], pivots[offset + 7], params);
		var wNet = Math.abs(pivots[offset + 3].price - pivots[offset].price);
		var yNet = Math.abs(pivots[offset + 7].price - pivots[offset + 4].price);
		var eq = SoftScores.equality(wNet, yNet, 0.25);
		return SoftScores.combine(a, b, eq);
	}

	public static function softScoreTriangle(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0.5;
		var a = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var c = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
		var e = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(a > 0 && c > 0)) return 0.5;
		return SoftScores.combine(
			SoftScores.fibRatio(c / a, p.phiInv, p.fibHitTol),
			SoftScores.fibRatio(e / c, p.phiInv, p.fibHitTol)
		);
	}

	public static function projectC(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ratio:Float = 1.0):Float {
		return RatioEngine.projectLeg(p0.price, p1.price, p2.price, ratio);
	}
}
