package musescript.indicators.geom;

/**
 * Soft equality / volume / ATR / time / fib-ratio multiples for confluence scoring.
 * Returns [0,1] soft scores — never hard rejects.
 */
class SoftScores {
	/** Relative equality of two magnitudes within `tol` fraction → 1, else linear falloff. */
	public static inline function equality(a:Float, b:Float, tol:Float = 0.1):Float {
		var den = Math.max(Math.abs(a), Math.abs(b));
		if (den < 1e-12) return 1.0;
		var err = Math.abs(a - b) / den;
		if (err <= tol) return 1.0;
		var soft = 1.0 - (err - tol) / (1.0 + tol);
		return soft < 0 ? 0.0 : soft;
	}

	/** Soft membership of `ratio` near a target Fib (e.g. 0.618) within `tol`. */
	public static inline function fibRatio(ratio:Float, target:Float, tol:Float = 0.08):Float {
		if (!Math.isFinite(ratio) || !Math.isFinite(target)) return 0.0;
		return equality(ratio, target, tol);
	}

	/**
	 * Best soft hit among common Fib targets (0.382 / 0.5 / 0.618 / 0.786 / 1.0 / 1.272 / 1.618).
	 * Used by EW corrective/impulse soft scoring — never gates hard rules.
	 */
	public static function bestFibHit(ratio:Float):Float {
		if (!Math.isFinite(ratio) || ratio <= 0) return 0.0;
		var best = 0.0;
		inline function consider(t:Float):Void {
			var s = fibRatio(ratio, t, 0.1);
			if (s > best) best = s;
		}
		consider(0.382); consider(0.5); consider(0.618); consider(0.786);
		consider(1.0); consider(1.272); consider(1.618); consider(2.0);
		return best;
	}

	/** Geometric mean of up to four scores in [0,1] (skips NaN / ignores zeros lightly). */
	public static function combine(a:Float, b:Float, c:Float = 1.0, d:Float = 1.0):Float {
		var prod = 1.0;
		var n = 0;
		inline function take(x:Float):Void {
			if (Math.isFinite(x) && x >= 0) {
				prod *= Math.max(0.05, Math.min(1.0, x));
				n++;
			}
		}
		take(a); take(b); take(c); take(d);
		if (n == 0) return 0.5;
		return Math.pow(prod, 1.0 / n);
	}

	/** Volume confirmation: current vs baseline. */
	public static inline function volumeConfirm(vol:Float, baseline:Float):Float {
		if (!(baseline > 0) || !Math.isFinite(vol)) return 0.5;
		var r = vol / baseline;
		if (r >= 1.0) return Math.min(1.0, 0.5 + 0.5 * (r - 1.0));
		return Math.max(0.0, 0.5 * r);
	}

	/** ATR multiple of a price move. */
	public static inline function atrMultiple(move:Float, atr:Float, targetMult:Float = 1.0):Float {
		if (!(atr > 0)) return 0.5;
		return equality(Math.abs(move) / atr, targetMult, 0.25);
	}

	/** Time equality of two bar spans. */
	public static inline function timeEquality(barsA:Int, barsB:Int, tol:Float = 0.15):Float {
		return equality(barsA * 1.0, barsB * 1.0, tol);
	}

	/**
	 * Alternation / symmetry soft score for wave lengths (bars).
	 * Prefers wave3 longer than wave1 and wave5 not dwarfing wave3.
	 */
	public static function impulseLengthSoft(w1:Float, w3:Float, w5:Float):Float {
		if (!(w1 > 0) || !(w3 > 0) || !(w5 > 0)) return 0.0;
		var notShortest3 = (w3 >= w1 || w3 >= w5) ? 1.0 : SoftScores.equality(w3, Math.max(w1, w5), 0.35);
		var ext = SoftScores.bestFibHit(w3 / w1);
		var five = SoftScores.bestFibHit(w5 / w1);
		return SoftScores.combine(notShortest3, ext, five);
	}
}
