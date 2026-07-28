package musescript.ew.mcmc;

import haxe.io.FPHelper;

/**
 * Deterministic, target-agnostic `exp`/`log` for the MCMC kernel's acceptance ratio.
 *
 * Native `Math.exp`/`Math.log` are NOT identically rounded across Graal-JVM and WASM/JS, so a chain
 * that uses them silently forks across backends. These approximations use ONLY IEEE-deterministic
 * operations (`+ - * /`, comparisons) plus raw bit access via `FPHelper` for exponent handling — all
 * of which produce identical bits on every Haxe target — with a FIXED iteration count (no
 * data-dependent loop length). Accuracy (~1e-12 rel.) is far tighter than an MH accept needs; the
 * point is byte-identical determinism, not last-ULP agreement with libm.
 */
class DetMath {
	static inline var LN2 = 0.6931471805599453;
	static inline var INV_LN2 = 1.4426950408889634;

	/** Natural log for x > 0 (NaN for x <= 0). frexp via bit surgery + atanh series on the mantissa. */
	public static function log(x:Float):Float {
		if (!(x > 0)) return Math.NaN;
		var b = FPHelper.doubleToI64(x);
		var hi = b.high;
		var e = ((hi >>> 20) & 0x7FF) - 1023;    // unbiased exponent (m in [1,2))
		var mHi = (hi & 0x800FFFFF) | (0x3FF << 20); // force exponent to 1023
		var m = FPHelper.i64ToDouble(b.low, mHi);
		// log(m) = 2 (s + s^3/3 + s^5/5 + …), s = (m-1)/(m+1), converges fast for m in [1,2)
		var s = (m - 1.0) / (m + 1.0);
		var s2 = s * s;
		var term = s;
		var k = 1.0;
		var sum = 0.0;
		for (_ in 0...14) {
			sum += term / k;
			term *= s2;
			k += 2.0;
		}
		return 2.0 * sum + e * LN2;
	}

	/** e^x. Range-reduce x = k·ln2 + r with |r| <= ln2/2, Taylor on r, scale by 2^k via exponent bits. */
	public static function exp(x:Float):Float {
		if (x != x) return Math.NaN; // NaN in, NaN out
		var k = Math.ffloor(x * INV_LN2 + 0.5); // nearest integer; floor is IEEE-exact
		var r = x - k * LN2;
		var term = 1.0;
		var sum = 1.0;
		for (i in 1...18) {
			term *= r / i;
			sum += term;
		}
		return sum * pow2i(k);
	}

	/** 2^k for integer-valued k, exact via IEEE exponent bits. */
	static function pow2i(k:Float):Float {
		var ki = Std.int(k);
		if (ki > 1023) return Math.POSITIVE_INFINITY;
		if (ki < -1022) return 0.0; // flush subnormal underflow to 0 (deterministic)
		var hi = (ki + 1023) << 20;
		return FPHelper.i64ToDouble(0, hi);
	}
}
