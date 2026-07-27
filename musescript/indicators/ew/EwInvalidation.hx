package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;

/** Price/bar level that kills (or soft-kills) a preferred EW count. */
typedef EwInvalidationLevel = {
	var price:Float;
	var bar:Float;
}

/**
 * Invalidation levels for ranked EW hypotheses — Frost & Prechter Ch1/Ch2 spirit.
 *
 * Composes over pivots + label only (no pattern-detection rewrite). Sibling pattern
 * expansion may add `diagonal_*` labels; those share motive invalidation.
 *
 * Ch1 hard spirit (Lessons 4–9):
 * - Motive: W2 never beyond start of W1 → structural kill = W1 origin (p0).
 * - Completed impulse/diagonal: same origin remains the count-kill if revisited;
 *   soft “next” depth guideline (Ch2) often watches prior 4th — see `softNextW4`.
 * - Zigzag: B beyond start of A kills sharp correction → invalidate = A origin (p0).
 * - Flat: B may exceed A origin (expanded/running); after ABC, break beyond C tip
 *   in the corrective direction questions “correction finished / new motive”.
 * - Triangle: break beyond wave-A extreme (widest actionary tip) kills contraction.
 * - Double zigzag: first W is a zigzag → invalidate = W origin (p0).
 */
class EwInvalidation {
	static inline function nanLevel():EwInvalidationLevel {
		return { price: Math.NaN, bar: Math.NaN };
	}

	static inline function atPivot(p:PivotPoint):EwInvalidationLevel {
		return { price: p.price, bar: p.bar * 1.0 };
	}

	/**
	 * Primary invalidation for `label` over `pivots[offset..]`.
	 * Returns NaN price/bar when the window is too short or label unknown.
	 */
	public static function forLabel(
		label:String,
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (pivots == null || label == null) return nanLevel();
		return switch (label) {
			// Motive family (incl. trunc/ext + diagonal_* from pattern expansion)
			case "impulse5", "impulse5_trunc", "impulse5_ext1", "impulse5_ext3", "impulse5_ext5",
				"diagonal", "diagonal_ending", "diagonal_leading":
				impulseOrDiagonal(pivots, offset);
			case "zigzag":
				zigzag(pivots, offset);
			case "flat", "flat_expanded", "flat_running":
				flat(pivots, offset);
			case "triangle", "triangle_expanding":
				triangle(pivots, offset);
			case "double_zigzag", "double_three":
				doubleZigzag(pivots, offset);
			default:
				nanLevel();
		};
	}

	/** Mutate hypothesis fields from pivots at `h.offset` (or explicit offset). */
	public static function apply(
		h:EwHypothesis,
		pivots:haxe.ds.Vector<PivotPoint>,
		?offset:Int
	):Void {
		var o = offset != null ? offset : h.offset;
		var inv = forLabel(h.label, pivots, o);
		h.invalidatePrice = inv.price;
		h.invalidateBar = inv.bar;
	}

	/**
	 * Motive / impulse / diagonal: kill beyond start of W1 (p0).
	 * Bull count dies below p0; bear count dies above p0.
	 * (Incomplete forming: W2 beyond p0 already hard-gated in ImpulseRules.)
	 */
	public static function impulseOrDiagonal(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset >= pivots.length) return nanLevel();
		// Completed 5-wave windows still use W1 origin as structural invalidatePrice.
		return atPivot(pivots[offset]);
	}

	/**
	 * Soft forward level after a completed 5-wave: end of W4 (p4).
	 * Ch2 depth: corrections often reach prior 4th; a break *through* W4 end
	 * against the impulse direction while expecting only a shallow next leg
	 * is a soft count warning (not the hard W1-origin kill).
	 */
	public static function softNextW4(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset + 4 >= pivots.length) return nanLevel();
		return atPivot(pivots[offset + 4]);
	}

	/** Zigzag: B beyond start of A kills → A origin (p0). */
	public static function zigzag(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset >= pivots.length) return nanLevel();
		return atPivot(pivots[offset]);
	}

	/**
	 * Flat subtypes: A origin is not a hard B-kill (expanded/running allow beyond).
	 * For completed ABC, C tip (p3) is the soft “still corrective vs new motive”
	 * invalidation — a further extreme in C's direction questions the count.
	 */
	public static function flat(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset + 3 >= pivots.length) return nanLevel();
		return atPivot(pivots[offset + 3]);
	}

	/**
	 * Contracting triangle: beyond wave-A tip (p1) — the widest typical actionary
	 * extreme — kills the contracting envelope (Ch1 triangle skeleton).
	 */
	public static function triangle(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset + 1 >= pivots.length) return nanLevel();
		return atPivot(pivots[offset + 1]);
	}

	/** Double zigzag W-X-Y: first W is a zigzag → W origin (p0). */
	public static function doubleZigzag(
		pivots:haxe.ds.Vector<PivotPoint>,
		offset:Int = 0
	):EwInvalidationLevel {
		if (offset >= pivots.length) return nanLevel();
		return atPivot(pivots[offset]);
	}
}
