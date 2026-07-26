package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SoftScores;

/**
 * Hard corrective (A-B-C) rules for v1 + soft Fib/time scores for lattice ranking.
 */
class CorrectiveRules {
	/**
	 * Three-wave zigzag/flat candidate over four pivots (0=start A, 1=A end,
	 * 2=B end, 3=C end).
	 */
	public static function isValidZigzag(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint):Bool {
		if (p0.direction == p1.direction) return false;
		if (p1.direction == p2.direction) return false;
		if (p2.direction == p3.direction) return false;
		var ab = Math.abs(p1.price - p0.price);
		var bc = Math.abs(p2.price - p1.price);
		var cd = Math.abs(p3.price - p2.price);
		if (ab <= 0) return false;
		// B retraces A by at least 0.382 and at most 0.99 (hard band)
		var retrace = bc / ab;
		if (retrace < 0.382 || retrace > 0.99) return false;
		// C at least 0.618 of A
		if (cd / ab < 0.618) return false;
		return true;
	}

	/**
	 * Soft score in (0,1] for a hard-valid zigzag — Fib proximity of B/C + time symmetry.
	 * Never used as a hard gate; lattice multiplies base rank by this.
	 */
	public static function softScore(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint):Float {
		var ab = Math.abs(p1.price - p0.price);
		if (!(ab > 0)) return 0.5;
		var bc = Math.abs(p2.price - p1.price);
		var cd = Math.abs(p3.price - p2.price);
		var bHit = SoftScores.bestFibHit(bc / ab);
		var cHit = SoftScores.bestFibHit(cd / ab);
		var tAB = p1.bar - p0.bar;
		var tBC = p2.bar - p1.bar;
		var tCD = p3.bar - p2.bar;
		var timeSoft = SoftScores.combine(
			SoftScores.timeEquality(tAB, tCD, 0.35),
			SoftScores.bestFibHit(tBC > 0 ? (tAB * 1.0) / tBC : 1.0)
		);
		return SoftScores.combine(bHit, cHit, timeSoft);
	}

	/** Project C target from A-B using RatioEngine extension ratios. */
	public static function projectC(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ratio:Float = 1.0):Float {
		return RatioEngine.projectLeg(p0.price, p1.price, p2.price, ratio);
	}
}
