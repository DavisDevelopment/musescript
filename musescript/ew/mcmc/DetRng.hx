package musescript.ew.mcmc;

import haxe.Int64;

/**
 * Deterministic PCG32 (XSH-RR). State advances in `haxe.Int64` — whose 64-bit semantics Haxe
 * guarantees identical on every target (native long on JVM, software emulation on JS/WASM, same
 * bits) — and the 32-bit output fold uses plain `Int` bit-ops (32-bit on all targets). The result
 * is a byte-identical random stream across Graal-JVM and WASM/JS for a given seed.
 *
 * This is the RNG foundation for the dual-compiled MCMC kernel (JVM compute + WASM demo): MH
 * acceptance is pure RNG, so a stream that differs across backends silently forks the posterior.
 * We deliberately avoid 32-bit `Int` multiply (lossy on JS) by keeping all state math in Int64.
 */
class DetRng {
	static var MULT:Int64 = Int64.make(0x5851F42D, 0x4C957F2D); // 6364136223846793005

	var state:Int64;
	var inc:Int64;

	public function new(seed:Int64, ?seq:Int64) {
		var s = seq != null ? seq : Int64.make(0, 0xDA3E39CB);
		inc = (s << 1) | Int64.make(0, 1); // must be odd
		state = Int64.make(0, 0);
		advance();
		state = state + seed;
		advance();
	}

	inline function advance():Void {
		state = state * MULT + inc;
	}

	/** Next 32-bit output (signed Int; interpret the bit pattern as unsigned where needed). */
	public function next():Int {
		var old = state;
		advance();
		var xs64 = ((old >>> 18) ^ old) >>> 27;
		var xs:Int = xs64.low; // low 32 bits (unchecked narrowing; toInt() would throw on >32 sig bits)
		var rot:Int = (old >>> 59).low & 31;
		return rotr32(xs, rot);
	}

	/** 32-bit rotate-right by `r` (0..31). Plain 32-bit Int ops — identical on JVM and JS/WASM. */
	static inline function rotr32(x:Int, r:Int):Int {
		return (x >>> r) | (x << ((32 - r) & 31));
	}

	/** Uniform Float in [0,1) from 32 bits; float arithmetic is IEEE-deterministic across targets. */
	public function nextUnit():Float {
		var u = next();
		var f = u < 0 ? (u + 4294967296.0) : (u + 0.0); // signed 32-bit → unsigned as double
		return f / 4294967296.0;
	}

	var haveGauss:Bool = false;
	var gaussCache:Float = 0.0;

	/**
	 * Standard-normal draw via the Marsaglia polar method — trig-free, so it stays inside the
	 * byte-identical op-set (nextUnit + DetMath.log + sqrt, all IEEE-deterministic). Box–Muller is
	 * avoided because it needs cos/sin, which are not identically rounded across targets.
	 */
	public function nextGaussian():Float {
		if (haveGauss) {
			haveGauss = false;
			return gaussCache;
		}
		var u = 0.0;
		var v = 0.0;
		var s = 0.0;
		do {
			u = 2.0 * nextUnit() - 1.0;
			v = 2.0 * nextUnit() - 1.0;
			s = u * u + v * v;
		} while (s >= 1.0 || s == 0.0);
		var mul = Math.sqrt(-2.0 * DetMath.log(s) / s); // sqrt is IEEE-correctly-rounded on all targets
		gaussCache = v * mul;
		haveGauss = true;
		return u * mul;
	}

	/** Uniform Int in [0, n) via rejection (no modulo bias); deterministic. n must be > 0. */
	public function nextInt(n:Int):Int {
		if (n <= 1) return 0;
		// threshold = 2^32 mod n, computed on doubles (exact for these magnitudes)
		var thresh = (4294967296.0 % n);
		while (true) {
			var u = next();
			var uf = u < 0 ? (u + 4294967296.0) : (u + 0.0);
			if (uf >= thresh) return Std.int(uf % n);
		}
	}
}
