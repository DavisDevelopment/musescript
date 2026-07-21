package musescript.indicators;

/**
 * Shared windowed-DFT math for the `fourier_*` builtins
 * (lib/FourierDecompose, lib/FourierRecompose, lib/FourierProjection,
 * lib/FourierDominantPeriod). MuseScript-native additions, NOT Wickra ports —
 * they follow the same lib/-file-per-builtin assembly line, and the math
 * lives here (package `musescript.indicators`, outside the macro-scanned
 * lib/ dir) so the four builtins share one implementation instead of four
 * embedded copies.
 *
 * Convention: real-input DFT over the window x[0..n-1] (oldest → newest),
 * synthesized as a sum of cosines
 *
 *   x[j] = Σ_{m=0..n/2} amp[m] · cos(2π·m·j/n + phase[m])
 *
 * with amp[0]·cos(phase[0]) the mean (DC) term and, for even n, bin n/2 the
 * Nyquist term — the scaling below makes that synthesis EXACT for real
 * inputs, which is what makes full-rank recomposition a hard test gate.
 */
class FourierMath {
	/** Full one-sided spectrum of the window: amp/phase per bin m = 0..n/2. */
	public static function spectrum(x:Array<Float>):{amp:Array<Float>, phase:Array<Float>} {
		var n = x.length;
		var half = n >> 1;
		var amp:Array<Float> = [];
		var phase:Array<Float> = [];
		for (m in 0...half + 1) {
			var re = 0.0, im = 0.0;
			var w = -2.0 * Math.PI * m / n;
			for (j in 0...n) {
				re += x[j] * Math.cos(w * j);
				im += x[j] * Math.sin(w * j);
			}
			var scale = (m == 0 || (n % 2 == 0 && m == half)) ? 1.0 / n : 2.0 / n;
			amp.push(Math.sqrt(re * re + im * im) * scale);
			phase.push(Math.atan2(im, re));
		}
		return { amp: amp, phase: phase };
	}

	/**
	 * Non-DC bins ranked by amplitude (descending; ties → lower frequency
	 * first, deterministically), truncated to at most k entries.
	 */
	public static function topBins(amp:Array<Float>, k:Int):Array<Int> {
		var bins = [for (m in 1...amp.length) m];
		bins.sort(function(a, b) {
			if (amp[a] < amp[b]) return 1;
			if (amp[a] > amp[b]) return -1;
			return a - b;
		});
		if (k < bins.length) bins = bins.slice(0, k);
		return bins;
	}

	/** DC + the given bins synthesized at (possibly fractional/future) sample index j. */
	public static function synth(n:Int, bins:Array<Int>, amp:Array<Float>, phase:Array<Float>, j:Float):Float {
		var v = amp[0] * Math.cos(phase[0]); // DC
		for (m in bins)
			v += amp[m] * Math.cos(2.0 * Math.PI * m * j / n + phase[m]);
		return v;
	}

	/** Least-squares line over the window: x[j] ≈ intercept + slope·j. */
	public static function linearFit(x:Array<Float>):{slope:Float, intercept:Float} {
		var n = x.length;
		var jm = (n - 1) / 2.0;
		var xm = 0.0;
		for (v in x) xm += v;
		xm /= n;
		var num = 0.0, den = 0.0;
		for (j in 0...n) {
			var dj = j - jm;
			num += dj * (x[j] - xm);
			den += dj * dj;
		}
		var slope = den == 0.0 ? 0.0 : num / den;
		return { slope: slope, intercept: xm - slope * jm };
	}

	/**
	 * Resolve an optional boolean arg (accepts Bool or numeric truthiness).
	 * Type-checked branch by branch: a `Dynamic == false` comparison compiles
	 * to a hard Double→Boolean cast on the JVM target (found by the GraalVM
	 * indicator bench — same strictness class as the garch11 arg bug).
	 */
	public static function boolArg(args:Array<Dynamic>, i:Int, def:Bool):Bool {
		if (i >= args.length || args[i] == null) return def;
		var v:Dynamic = args[i];
		if (Std.isOfType(v, Bool)) return (v : Bool);
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0.0;
		return def;
	}
}
