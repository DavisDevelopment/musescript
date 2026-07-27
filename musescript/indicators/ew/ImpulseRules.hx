package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SoftScores;

/**
 * Hard motive / impulse / diagonal rules — Frost & Prechter Ch1 (Lessons 4–5).
 * Soft Fib/length scores use EwPhiParams (never as hard gates).
 *
 * Labels emitted by lattice helpers:
 *   impulse5 | impulse5_trunc | impulse5_ext1 | impulse5_ext3 | impulse5_ext5
 *   diagonal_ending | diagonal_leading
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

	/**
	 * Truncated / failed fifth: W5 fails to exceed W3 tip in motive direction.
	 * Still a valid impulse when other hard rules hold (Frost & Prechter).
	 */
	public static function isTruncatedFifth(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Bool {
		if (offset + 5 >= pivots.length) return false;
		var p0 = pivots[offset];
		var p1 = pivots[offset + 1];
		var p3 = pivots[offset + 3];
		var p5 = pivots[offset + 5];
		var up = p1.price > p0.price;
		if (up) return p5.price <= p3.price + 1e-12;
		return p5.price >= p3.price - 1e-12;
	}

	/**
	 * Diagonal subtype from wedge geometry (price skeleton only).
	 * @return 0=none, 1=ending (contracting), 2=leading (expanding / non-contracting)
	 */
	public static function diagonalKind(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0):Int {
		if (!isValidDiagonal(pivots, offset)) return 0;
		return isContractingWedge(pivots, offset) ? 1 : 2;
	}

	public static function diagonalLabel(kind:Int):String {
		return switch (kind) {
			case 1: "diagonal_ending";
			case 2: "diagonal_leading";
			default: "unknown";
		};
	}

	/**
	 * Which motive wave is extended (longest among 1/3/5, with soft φ bias).
	 * Hard: pick longest; ties break 3 > 5 > 1 (handbook preference).
	 * Soft: require extended wave ≥ extensionMinVsPeer × next-longest (params).
	 * @return 0=none/ambiguous, 1, 3, or 5
	 */
	public static function extensionWhich(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Int {
		var p = params != null ? params : EwPhiParams.current();
		if (offset + 5 >= pivots.length) return 0;
		var w1 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var w3 = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
		var w5 = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(w1 > 0 && w3 > 0 && w5 > 0)) return 0;

		var which = 3;
		var longest = w3;
		if (w1 > longest + 1e-12) { longest = w1; which = 1; }
		if (w5 > longest + 1e-12) { longest = w5; which = 5; }
		// ties: prefer 3, then 5, then 1
		if (Math.abs(w3 - longest) <= 1e-12) which = 3;
		else if (Math.abs(w5 - longest) <= 1e-12 && which != 3) which = 5;

		var peer = which == 3 ? Math.max(w1, w5) : (which == 1 ? Math.max(w3, w5) : Math.max(w1, w3));
		if (!(peer > 0)) return 0;
		if (longest < peer * p.extensionMinVsPeer) return 0;
		return which;
	}

	/**
	 * Primary impulse label for lattice emission.
	 * Truncation wins over extension tagging (failure is the rarer structural fact).
	 * Else extension label when clear; else plain impulse5.
	 */
	public static function impulseLabel(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):String {
		if (!isValidFiveWave(pivots, offset)) return "unknown";
		if (isTruncatedFifth(pivots, offset)) return "impulse5_trunc";
		var ext = extensionWhich(pivots, offset, params);
		return switch (ext) {
			case 1: "impulse5_ext1";
			case 3: "impulse5_ext3";
			case 5: "impulse5_ext5";
			default: "impulse5";
		};
	}

	/** True if label is any impulse5* family (incl. trunc/ext). */
	public static inline function isImpulseFamily(label:String):Bool {
		return label != null && (label == "impulse5"
			|| label == "impulse5_trunc"
			|| label == "impulse5_ext1"
			|| label == "impulse5_ext3"
			|| label == "impulse5_ext5");
	}

	/** True if label is any diagonal_* family (legacy `diagonal` included). */
	public static inline function isDiagonalFamily(label:String):Bool {
		return label != null && (label == "diagonal"
			|| label == "diagonal_ending"
			|| label == "diagonal_leading");
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
		var base = SoftScores.combine(lenSoft, w2re, w4re, t13);
		if (isTruncatedFifth(pivots, offset)) {
			// Truncation is rare — soft-penalize unless W5 ≈ W3 tip
			var tipGap = Math.abs(p5.price - p3.price) / Math.max(1e-12, w3);
			var truncSoft = SoftScores.fibRatio(tipGap, 0.0, p.truncTipTol);
			base = SoftScores.combine(base, Math.max(0.35, truncSoft * p.truncSoftWeight));
		}
		var ext = extensionWhich(pivots, offset, p);
		if (ext == 3) {
			base = SoftScores.combine(base, p.bestHit(w3 / w1, p.w3ExtTargets, p.w3ExtN));
		} else if (ext == 5) {
			base = SoftScores.combine(base, p.bestHit(w5 / w1, p.w5ExtTargets, p.w5ExtN));
		} else if (ext == 1) {
			base = SoftScores.combine(base, SoftScores.fibRatio(w1 / w3, p.phi, p.fibHitTol));
		}
		return base;
	}

	public static function softScoreDiagonal(pivots:haxe.ds.Vector<PivotPoint>, offset:Int = 0, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		var base = softScoreFiveWave(pivots, offset, p) * 0.9;
		var kind = diagonalKind(pivots, offset);
		if (kind == 1) {
			// Ending: prefer strong contraction of actionary spans
			var w1 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
			var w3 = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
			var w5 = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
			if (w1 > 0 && w3 > 0) {
				base = SoftScores.combine(base,
					SoftScores.fibRatio(w3 / w1, p.phiInv, p.fibHitTol + 0.05),
					SoftScores.fibRatio(w5 / w3, p.phiInv, p.fibHitTol + 0.08));
			}
		} else if (kind == 2) {
			// Leading: mild expansion or near-equality of early actionaries
			var w1 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
			var w3 = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
			if (w1 > 0) {
				base = SoftScores.combine(base, SoftScores.equality(w3, w1, 0.25));
			}
		}
		return base;
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

	/**
	 * Contracting wedge: actionary lengths shrink (W5 < W3 < W1 loosely)
	 * and corrective tips approach (W4 span into W1 territory deeper than W2).
	 */
	static function isContractingWedge(pivots:haxe.ds.Vector<PivotPoint>, offset:Int):Bool {
		var w1 = Math.abs(pivots[offset + 1].price - pivots[offset].price);
		var w3 = Math.abs(pivots[offset + 3].price - pivots[offset + 2].price);
		var w5 = Math.abs(pivots[offset + 5].price - pivots[offset + 4].price);
		if (!(w1 > 0)) return false;
		// Ending diagonals contract: W5 < W1 and W3 <= W1 * 1.05
		if (!(w5 < w1 * 0.98 && w3 <= w1 * 1.05)) return false;
		if (!(w5 <= w3 * 1.02)) return false;
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
