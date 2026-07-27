package musescript.evo;

/**
 * Monte-Carlo fan shock engine for `PSNoise` projections (PROJECTION_COEVOLUTION_PLAN.md §2, §5).
 *
 * A `PSNoise` fan is `K` sample paths `base_t + z_i * vol_t`. For a *location-scale* noise family
 * (Gaussian, Student-t) the `K` standardized shocks `z_i` are a fixed, seed-determined set, so every
 * fan reduction the policy reads is CLOSED-FORM in `(base_t, vol_t)` with compile-time-constant
 * coefficients:
 *
 *   sample_i = base + z_i    * vol
 *   p_q      = base + Q(q)   * vol          (Q = empirical quantile of the shocks)
 *   mean     = base + mean(z)* vol
 *   spread   = (Q(0.95) - Q(0.05)) * vol
 *
 * so `Expand` bakes those constants straight into MuseScript arithmetic — no runtime builtin, no
 * cross-backend dispatch, and EXACT (no Monte-Carlo sampling error) rather than approximate. The `K`
 * "samples" manifest as the `K` shocks this class produces.
 *
 * Determinism only needs to hold WITHIN the process that renders (the shocks are baked into source as
 * numeric literals, then the rendered strategy is what runs), so a plain Park-Miller MINSTD generator
 * in exact double arithmetic is enough and stays identical across targets anyway.
 *
 * Block-bootstrap (`NBlockBootstrap`) is NOT location-scale and depends on the tape's own past
 * residuals, so it cannot be a render-time constant — it needs a runtime provider/column (owed, P1).
 *
 * «κύκλος ἀστέρων· κλῆρος πίπτει, μοῖρα μένει.»
 */
class McFan {
	/** Park-Miller MINSTD state from an arbitrary seed. State kept in a 1-element array so the
	 * generator is a cheap closure-free mutable handle. Product `16807 * (2^31-2)` stays < 2^53, so
	 * every step is exact in double on every target. */
	static function seedState(seed:Int):Array<Float> {
		var s = seed % 2147483646;
		if (s < 0)
			s += 2147483646;
		return [(s + 1) * 1.0]; // in [1, 2^31-2]
	}

	static function nextUniform(s:Array<Float>):Float {
		s[0] = (s[0] * 16807.0) % 2147483647.0;
		return s[0] / 2147483647.0; // (0, 1)
	}

	/**
	 * `K` standardized shocks (mean ≈ 0, unit scale) under `model`, deterministic in `seed`.
	 * Only location-scale families render to closed-form arithmetic; the rest throw (owed).
	 */
	public static function shocks(seed:Int, k:Int, model:NoiseModel):Array<Float> {
		if (k < 1)
			k = 1;
		var s = seedState(seed);
		return switch (model) {
			case NGaussian:
				[for (_ in 0...k) invNorm(clampP(nextUniform(s)))];
			case NStudentT(dof):
				// t = z / sqrt(chi2_dof / dof); chi2 = Σ of `dof` squared standard normals.
				var d = dof < 1 ? 1 : dof;
				[
					for (_ in 0...k) {
						var z = invNorm(clampP(nextUniform(s)));
						var chi2 = 0.0;
						for (_ in 0...d) {
							var g = invNorm(clampP(nextUniform(s)));
							chi2 += g * g;
						}
						z / Math.sqrt(chi2 / d);
					}
				];
			case NBlockBootstrap(_):
				throw "McFan.shocks: NBlockBootstrap is not a render-time constant (needs tape residuals; owed P1)";
		};
	}

	static inline function clampP(p:Float):Float {
		return p < 1e-9 ? 1e-9 : (p > 1 - 1e-9 ? 1 - 1e-9 : p);
	}

	public static function sortedCopy(a:Array<Float>):Array<Float> {
		var c = a.copy();
		c.sort(function(x, y) return x < y ? -1 : (x > y ? 1 : 0));
		return c;
	}

	/** Linear-interpolated empirical quantile over an ascending-sorted array. */
	public static function quantile(sortedAsc:Array<Float>, q:Float):Float {
		var n = sortedAsc.length;
		if (n == 0)
			return 0;
		if (n == 1)
			return sortedAsc[0];
		var pos = q * (n - 1);
		var lo = Std.int(Math.floor(pos));
		if (lo < 0)
			lo = 0;
		var hi = lo + 1 >= n ? n - 1 : lo + 1;
		var frac = pos - lo;
		return sortedAsc[lo] * (1 - frac) + sortedAsc[hi] * frac;
	}

	public static function mean(a:Array<Float>):Float {
		if (a.length == 0)
			return 0;
		var s = 0.0;
		for (i in 0...a.length)
			s += a[i];
		return s / a.length;
	}

	/**
	 * Inverse standard-normal CDF (Acklam's rational approximation, |abs err| < 1.15e-9). Maps a
	 * uniform draw in (0,1) to a standard normal.
	 */
	public static function invNorm(p:Float):Float {
		var a0 = -3.969683028665376e+01, a1 = 2.209460984245205e+02, a2 = -2.759285104469687e+02,
			a3 = 1.383577518672690e+02, a4 = -3.066479806614716e+01, a5 = 2.506628277459239e+00;
		var b0 = -5.447609879822406e+01, b1 = 1.615858368580409e+02, b2 = -1.556989798598866e+02,
			b3 = 6.680131188771972e+01, b4 = -1.328068155288572e+01;
		var c0 = -7.784894002430293e-03, c1 = -3.223964580411365e-01, c2 = -2.400758277161838e+00,
			c3 = -2.549732539343734e+00, c4 = 4.374664141464968e+00, c5 = 2.938163982698783e+00;
		var d0 = 7.784695709041462e-03, d1 = 3.224671290700398e-01, d2 = 2.445134137142996e+00,
			d3 = 3.754408661907416e+00;
		var plow = 0.02425;
		var phigh = 1 - plow;
		if (p < plow) {
			var q = Math.sqrt(-2 * Math.log(p));
			return (((((c0 * q + c1) * q + c2) * q + c3) * q + c4) * q + c5)
				/ ((((d0 * q + d1) * q + d2) * q + d3) * q + 1);
		} else if (p <= phigh) {
			var q = p - 0.5;
			var r = q * q;
			return (((((a0 * r + a1) * r + a2) * r + a3) * r + a4) * r + a5) * q
				/ (((((b0 * r + b1) * r + b2) * r + b3) * r + b4) * r + 1);
		} else {
			var q = Math.sqrt(-2 * Math.log(1 - p));
			return -(((((c0 * q + c1) * q + c2) * q + c3) * q + c4) * q + c5)
				/ ((((d0 * q + d1) * q + d2) * q + d3) * q + 1);
		}
	}
}
