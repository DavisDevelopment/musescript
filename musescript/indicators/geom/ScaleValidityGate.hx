package musescript.indicators.geom;

/**
 * Scale-validity gate. Preferred: MF-DFA Δα width; v1 ships Hurst (+ multi-scale) proxies.
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

	/**
	 * Multi-scale Hurst consistency: when short/mid/long H agree (low dispersion) and
	 * the mean is away from 0.5, geometry tools are more trustworthy.
	 * Pass NaN for unknown scales — they are skipped.
	 */
	public static function fromHurstScales(hShort:Float, hMid:Float, hLong:Float):Float {
		var sum = 0.0;
		var sumSq = 0.0;
		var n = 0;
		inline function take(h:Float):Void {
			if (Math.isFinite(h)) {
				sum += h;
				sumSq += h * h;
				n++;
			}
		}
		take(hShort); take(hMid); take(hLong);
		if (n == 0) return 0.5;
		var mean = sum / n;
		var base = fromHurst(mean);
		if (n == 1) return base;
		var var_ = Math.max(0.0, sumSq / n - mean * mean);
		var disp = Math.sqrt(var_);
		// Low cross-scale dispersion → boost; high → damp toward 0.5
		var consistency = 1.0 - Math.min(1.0, disp * 6.0);
		return Math.min(1.0, 0.55 * base + 0.45 * SoftScores.combine(base, consistency));
	}

	/** Interface stub for a future MF-DFA implementation. */
	public static function fromMfDfaDeltaAlpha(deltaAlpha:Float):Float {
		if (!Math.isFinite(deltaAlpha) || deltaAlpha < 0) return 0.5;
		return Math.min(1.0, deltaAlpha * 5.0);
	}
}
