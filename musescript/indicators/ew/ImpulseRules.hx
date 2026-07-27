package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SoftScores;

/**
 * Hard motive / impulse / diagonal rules — Frost & Prechter Ch1 (Lessons 4–5).
 * Soft Fib/length scores use EwPhiParams (never as hard gates).
 */
class ImpulseRules {
	/** Six pivots p0..p5 = tips of W1..W5 (start of W1 is p0). */
	public static function isValidMotive(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (offset + 5 >= pivots.length) return false;
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p2 = pivots[offset + 2];
		var p3 = pivots[offset + 3];
		var p4 = pivots[offset + 4];
		var p5 = pivots[offset + 5];
		if (!alternates(p0, p1, p2, p3, p4, p5)) return false;

		var w1 = Math.abs(p1.price - p0.price);
		var w2 = Math.abs(p2.price - p1.price);
		var w3 = Math.abs(p3.price - p2.price);
		var w4 = Math.abs(p4.price - p3.price);
		var w5 = Math.abs(p5.price - p4.price);
		if (!(w1 > 0 && w3 > 0 && w5 > 0)) return false;

		if (w2 > w1 + 1e-12) return false;
		if (w4 > w3 + 1e-12) return false;

		var up = p1.price > p0.price;
		if (up && p3.price <= p1.price + 1e-12) return false;
		if (!up && p3.price >= p1.price - 1e-12) return false;

		if (w3 <= w1 + 1e-12 && w3 <= w5 + 1e-12) return false;
		return true;
	}

	/** Impulse: motive + no W4/W1 overlap. */
	public static function isValidFiveWave(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (!isValidMotive(pivots, offset)) return false;
		return !wave4OverlapsWave1(pivots, offset);
	}

	/** Diagonal skeleton: motive + W4 overlaps W1. */
	public static function isValidDiagonal(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (!isValidMotive(pivots, offset)) return false;
		return wave4OverlapsWave1(pivots, offset);
	}

	public static function wave4OverlapsWave1(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p4 = pivots[offset + 4];
		var lo = Math.min(p0.price, p1.price);
		var hi = Math.max(p0.price, p1.price);
		return p4.price >= lo - 1e-12 && p4.price <= hi + 1e-12;
	}

	public static function softScoreFiveWave(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
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
		var w2re = p.bestHit(w2 / w1, p.w2RetraceTargets, p.w2RetraceN);
		var w4re = p.bestHit(w3 > 0 ? w4 / w3 : w4 / w1, p.w4RetraceTargets, p.w4RetraceN);
		var t13 = SoftScores.timeEquality(p1.bar - p0.bar, p3.bar - p2.bar, p.timeHitTol);
		return SoftScores.combine(lenSoft, w2re, w4re, t13);
	}

	/** W1–W4 skeleton for older 5-arg callers. */
	public static function isValidImpulse(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, p4:PivotPoint):Bool {
		if (p0.direction == p1.direction) return false;
		if (p1.direction == p2.direction) return false;
		if (p2.direction == p3.direction) return false;
		if (p3.direction == p4.direction) return false;
		var w1 = Math.abs(p1.price - p0.price);
		var w2 = Math.abs(p2.price - p1.price);
		var w3 = Math.abs(p3.price - p2.price);
		if (!(w1 > 0 && w3 > 0)) return false;
		if (w2 > w1 + 1e-12) return false;
		var up = p1.price > p0.price;
		if (up && p3.price <= p1.price + 1e-12) return false;
		if (!up && p3.price >= p1.price - 1e-12) return false;
		var lo = Math.min(p0.price, p1.price);
		var hi = Math.max(p0.price, p1.price);
		if (p4.price >= lo - 1e-12 && p4.price <= hi + 1e-12) return false;
		return true;
	}

	static function alternates(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, p3:PivotPoint, p4:PivotPoint, p5:PivotPoint):Bool {
		return p0.direction != p1.direction
			&& p1.direction != p2.direction
			&& p2.direction != p3.direction
			&& p3.direction != p4.direction
			&& p4.direction != p5.direction;
	}
}
