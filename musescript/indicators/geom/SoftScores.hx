package musescript.indicators.geom;

/**
 * Soft equality / volume / ATR / time multiples for confluence scoring.
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
}
