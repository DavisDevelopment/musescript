package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SoftScores;

/**
 * Hard impulse (1-2-3-4-5) rules — Neely/Prechter subset for v1.
 * Soft Fib/length scores refine lattice ranking; degree nesting stays out of scope.
 */
class ImpulseRules {
	/**
	 * Validate five alternating pivots as a potential impulse ending at pivots[4].
	 * Rules enforced:
	 * 1. Wave 2 does not retrace beyond start of 1
	 * 2. Wave 3 is not the shortest among 1,3,5 (magnitude)
	 * 3. Wave 4 does not overlap wave 1 price territory (strict for v1)
	 */
	public static function isValidImpulse(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, p4:PivotPoint):Bool {
		// Directions must alternate starting from p0→p1
		if (p0.direction == p1.direction) return false;
		if (p1.direction == p2.direction) return false;
		if (p2.direction == p3.direction) return false;
		if (p3.direction == p4.direction) return false;

		var w1 = Math.abs(p1.price - p0.price);
		var w3 = Math.abs(p3.price - p2.price);
		// Need wave 5 tip — caller supplies only through wave 4 end at p4 when checking 1-4;
		// Full 5-wave uses six pivots; this overload checks waves 1-4 skeleton + partial 5 start.
		if (w1 <= 0 || w3 <= 0) return false;

		// Wave 2 retrace: p2 must stay within [p0, p1] interval
		var lo01 = Math.min(p0.price, p1.price);
		var hi01 = Math.max(p0.price, p1.price);
		if (p2.price < lo01 || p2.price > hi01) return false;

		// Wave 4 must not enter wave 1 territory
		var lo12 = Math.min(p0.price, p1.price);
		var hi12 = Math.max(p0.price, p1.price);
		if (p4.price >= lo12 && p4.price <= hi12) return false;

		return true;
	}

	/** Full five-wave check over six pivots (0..5). */
	public static function isValidFiveWave(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (offset + 5 >= pivots.length) return false;
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p2 = pivots[offset + 2];
		var p3 = pivots[offset + 3];
		var p4 = pivots[offset + 4];
		var p5 = pivots[offset + 5];
		if (!isValidImpulse(p0, p1, p2, p3, p4)) return false;
		var w1 = Math.abs(p1.price - p0.price);
		var w3 = Math.abs(p3.price - p2.price);
		var w5 = Math.abs(p5.price - p4.price);
		// Wave 3 not shortest
		if (w3 <= w1 && w3 <= w5) return false;
		// Wave 5 tip direction continues impulse
		var impulseUp = p1.price > p0.price;
		if (impulseUp && p5.price <= p3.price) return false;
		if (!impulseUp && p5.price >= p3.price) return false;
		return true;
	}

	/** Soft Fib/length score for a hard-valid five-wave (six pivots). */
	public static function softScoreFiveWave(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Float {
		if (offset + 5 >= pivots.length) return 0.5;
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p2 = pivots[offset + 2];
		var p3 = pivots[offset + 3];
		var p4 = pivots[offset + 4];
		var p5 = pivots[offset + 5];
		var w1 = Math.abs(p1.price - p0.price);
		var w2 = Math.abs(p2.price - p1.price);
		var w3 = Math.abs(p3.price - p2.price);
		var w4 = Math.abs(p4.price - p3.price);
		var w5 = Math.abs(p5.price - p4.price);
		if (!(w1 > 0)) return 0.5;
		var lenSoft = SoftScores.impulseLengthSoft(w1, w3, w5);
		var w2re = SoftScores.bestFibHit(w2 / w1);
		var w4re = SoftScores.bestFibHit(w4 / w3 > 0 ? w4 / w3 : w4 / w1);
		var t13 = SoftScores.timeEquality(p1.bar - p0.bar, p3.bar - p2.bar, 0.4);
		return SoftScores.combine(lenSoft, w2re, w4re, t13);
	}
}
