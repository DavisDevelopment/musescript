package musescript.indicators.geom;

/**
 * Scale-validity gate. Preferred: MF-DFA Δα width; v1 ships a Hurst-based proxy.
 * Returns [0,1] — 1 = scale looks fractal/valid for geometric tools.
 */
class ScaleValidityGate {
	/**
	 * Hurst proxy: H near 0.5 → random (lower validity for directional geometry);
	 * H away from 0.5 (trending or mean-reverting structure) → higher.
	 * `deltaAlpha` stub reserved for future MF-DFA width.
	 */
	public static function fromHurst(h:Float, ?deltaAlpha:Float):Float {
		if (!Math.isFinite(h)) return 0.5;
		var dist = Math.abs(h - 0.5);
		var score = Math.min(1.0, dist * 4.0); // H=0.75 → 1.0
		if (deltaAlpha != null && Math.isFinite(deltaAlpha)) {
			// Wider multifractal spectrum → slightly higher confidence
			score = Math.min(1.0, 0.7 * score + 0.3 * Math.min(1.0, deltaAlpha * 5.0));
		}
		return score;
	}

	/** Interface stub for a future MF-DFA implementation. */
	public static function fromMfDfaDeltaAlpha(deltaAlpha:Float):Float {
		if (!Math.isFinite(deltaAlpha) || deltaAlpha < 0) return 0.5;
		return Math.min(1.0, deltaAlpha * 5.0);
	}
}
