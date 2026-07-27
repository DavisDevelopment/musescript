package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SoftScores;

/**
 * Hard corrective rules — Frost & Prechter Ch1 (Lessons 6–8).
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
		// B does not exceed start of A (sharp zigzag)
		var upA = p1.price > p0.price;
		if (upA) {
			// A up → B must remain above start of A
			if (p2.price <= p0.price + 1e-12) return false;
		} else {
			// A down → B must remain below start of A
			if (p2.price >= p0.price - 1e-12) return false;
		}
		if (cd / ab < p.zigzagCMinVsA) return false;
		return true;
	}

	/**
	 * Flat A-B-C (3-3-5 price skeleton): B returns near or beyond start of A;
	 * C ends near/beyond end of A. Uses param bands — still a hard structural gate for lattice.
	 */
	public static function isValidFlat(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):Bool {
		var p = params != null ? params : EwPhiParams.current();
		if (p0.direction == p1.direction) return false;
		if (p1.direction == p2.direction) return false;
		if (p2.direction == p3.direction) return false;
		var ab = Math.abs(p1.price - p0.price);
		if (!(ab > 0)) return false;
		var bFromStart = Math.abs(p2.price - p0.price) / ab;
		// Regular: B near start of A; expanded: B beyond start in corrective direction
		var near = bFromStart <= (1.0 - p.flatBNear) + p.fibHitTol
			|| Math.abs(p2.price - p0.price) / ab <= (1.0 - p.flatBNear) + 0.15;
		var beyond = false;
		var upA = p1.price > p0.price;
		// Corrective flat after up impulse: A down. After down: A up.
		// B beyond start of A means B goes past p0 in the direction opposite to A.
		if (upA) beyond = p2.price < p0.price - p.flatBBeyond * ab;
		else beyond = p2.price > p0.price + p.flatBBeyond * ab;
		if (!near && !beyond) {
			// also accept B very close to p0
			if (Math.abs(p2.price - p0.price) / ab > 0.25) return false;
		}
		var cVsA = Math.abs(p3.price - p2.price) / ab;
		if (cVsA < 0.5) return false;
		return true;
	}

	/** Triangle stub: five alternating legs (six pivots) with contracting net range — soft gate. */
	public static function isValidTriangleStub(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (offset + 5 >= pivots.length) return false;
		for (i in 0...5) {
			if (pivots[offset + i].direction == pivots[offset + i + 1].direction) return false;
		}
		var first = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var last = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(first > 0)) return false;
		// Contracting tendency: last leg shorter than first
		return last <= first * 0.95;
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

	public static function projectC(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ratio:Float = 1.0):Float {
		return RatioEngine.projectLeg(p0.price, p1.price, p2.price, ratio);
	}
}
