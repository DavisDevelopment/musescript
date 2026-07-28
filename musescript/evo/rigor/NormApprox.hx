package musescript.evo.rigor;

/**
 * Deterministic normal CDF / inverse-CDF approximations for PSR/DSR.
 * Hart / Beasley–Springer–Moro style — pure arithmetic, no libm erf.
 */
class NormApprox {
	/** Standard normal CDF Φ(x). Absolute error ≲ 7.5e-8. */
	public static function cdf(x:Float):Float {
		if (Math.isNaN(x)) return Math.NaN;
		if (x < -8) return 0;
		if (x > 8) return 1;
		var t = 1.0 / (1.0 + 0.2316419 * Math.abs(x));
		var d = 0.3989422804014327 * Math.exp(-0.5 * x * x); // 1/sqrt(2π)
		var p = d * t * (0.319381530
			+ t * (-0.356563782
			+ t * (1.781477937
			+ t * (-1.821255978
			+ t * 1.330274429))));
		return x >= 0 ? 1.0 - p : p;
	}

	/**
	 * Approximate Φ^{-1}(p) for p ∈ (0,1). Beasley–Springer–Moro rational approximation.
	 * Absolute error typically < 1e-6 on (1e-6, 1-1e-6).
	 */
	public static function invCdf(p:Float):Float {
		if (!(p > 0 && p < 1)) return Math.NaN;
		var pp = p < 0.5 ? p : 1.0 - p;
		var r = Math.sqrt(-2.0 * Math.log(pp));
		// x = r − (a0+a1 r+a2 r²)/(1+b1 r+b2 r²+b3 r³)
		var x = r - ((2.515517 + 0.802853 * r + 0.010328 * r * r)
			/ (1.0 + 1.432788 * r + 0.189269 * r * r + 0.001308 * r * r * r));
		return p < 0.5 ? -x : x;
	}
}
