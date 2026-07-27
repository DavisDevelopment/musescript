package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SoftScores;

/**
 * Ch2 guidelines — soft only (Frost & Prechter Lessons 10–15).
 * Never hard-reject; multiply lattice scores.
 */
class EwGuidelines {
	/**
	 * Alternation within impulses: if W2 is "sharp" (deep retrace), prefer W4 "sideways" (shallow),
	 * and vice versa. Returns [0,1] soft score.
	 */
	public static function alternationImpulse(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0.5;
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p2 = pivots[offset + 2];
		var p3 = pivots[offset + 3];
		var p4 = pivots[offset + 4];
		var w1 = Math.abs(p1.price - p0.price);
		var w2 = Math.abs(p2.price - p1.price);
		var w3 = Math.abs(p3.price - p2.price);
		var w4 = Math.abs(p4.price - p3.price);
		if (!(w1 > 0 && w3 > 0)) return 0.5;
		var r2 = w2 / w1;
		var r4 = w4 / w3;
		var sharp2 = r2 >= p.half;
		var sharp4 = r4 >= p.half;
		// Prefer opposite styles
		var alt = (sharp2 != sharp4) ? 1.0 : SoftScores.equality(r2, 1.0 - r4, p.equalityTol);
		return Math.min(1.0, alt * p.alternationWeight);
	}

	/** Equality guideline: when W3 longest, prefer |W5| ≈ |W1|. */
	public static function equalityOneFive(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0.5;
		var w1 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var w3 = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
		var w5 = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(w1 > 0 && w3 > 0 && w5 > 0)) return 0.5;
		if (w3 < w1 || w3 < w5) return 0.55; // guideline less relevant
		var eq = SoftScores.equality(w1, w5, p.equalityTol);
		return Math.min(1.0, eq * p.equalityOneFiveWeight);
	}

	/**
	 * Depth guideline: correction tends to end in prior fourth-wave territory.
	 * Here: W2 or zigzag depth soft-hit against handbook Fib depths.
	 */
	public static function depthSoft(retraceFrac:Float, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (!Math.isFinite(retraceFrac)) return 0.5;
		var hit = SoftScores.combine(
			SoftScores.fibRatio(retraceFrac, p.oneMinusPhiInv, p.fibHitTol),
			SoftScores.fibRatio(retraceFrac, p.half, p.fibHitTol),
			SoftScores.fibRatio(retraceFrac, p.phiInv, p.fibHitTol)
		);
		return Math.min(1.0, hit * p.depthPriorFourthWeight);
	}

	/** Parallel-channel "right look": midpoints of W2/W4 vs line W0–W3 (crude). */
	public static function channelSoft(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 4 >= pivots.length) return 0.5;
		var a = pivots[offset].price;
		var b = pivots[offset + 2].price;
		var c = pivots[offset + 4].price;
		// Expect roughly linear progression of odd waves
		var mid = (a + c) * 0.5;
		var hit = SoftScores.equality(b, mid, 0.2);
		return Math.min(1.0, hit * p.channelWeight);
	}

	/** Combine impulse guideline bundle. */
	public static function scoreImpulse(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		return SoftScores.combine(
			alternationImpulse(pivots, offset, params),
			equalityOneFive(pivots, offset, params),
			channelSoft(pivots, offset, params)
		);
	}
}
