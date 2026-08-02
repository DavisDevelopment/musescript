package musescript.tools;

import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorRegistry;
import musescript.indicators.IndicatorSpec;
import musescript.types.MuseType;

/**
 * Exact-output snapshot of EVERY registered indicator, for refactors that must be
 * numerically neutral.
 *
 * Built for the `Array.shift()` → `RingBuffer` migration (ALGORITHM_AUDIT.md §2): that change
 * swaps the window-eviction mechanism in ~200 indicators and is supposed to alter throughput
 * and NOTHING else. "Supposed to" is not evidence, so this dumps every indicator's full output
 * series over a fixed synthetic tape; run it before and after and diff the two files. A single
 * changed digit anywhere shows up as a diff line naming the indicator.
 *
 * Deliberately self-contained: the synthetic tape is generated here from a fixed seed rather
 * than loaded from `data/`, so the snapshot is reproducible on any machine and in CI without
 * depending on tape files that may not be checked in.
 *
 *   haxe golden.hxml && node build/js/indicator-golden.js > /tmp/golden-before.txt
 *   ...migrate...
 *   haxe golden.hxml && node build/js/indicator-golden.js > /tmp/golden-after.txt
 *   diff /tmp/golden-before.txt /tmp/golden-after.txt   # must be empty
 *
 * Values print with 17 significant digits (`%.17g`-equivalent) so the comparison is exact to
 * the last bit of a Float, not merely to display precision.
 */
class IndicatorGolden {
	static inline var BARS = 260;
	static inline var SEED = 20260802;

	/** Deterministic OHLCV. Mixed regimes (trend + cycle + noise) so window-based indicators
	 *  actually exercise their eviction paths rather than sitting on a flat series. */
	static function tape(n:Int, seed:Int):Array<Bar> {
		var s = seed;
		inline function rnd():Float {
			// xorshift32 — local to this file; the tape only needs to be fixed, not high-quality.
			s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
			return ((s & 0x7FFFFFFF) : Float) / 2147483648.0;
		}
		var bars:Array<Bar> = [];
		var px = 100.0;
		for (i in 0...n) {
			var drift = Math.sin(i * 0.05) * 1.2 + Math.sin(i * 0.011) * 2.5;
			px = Math.max(1.0, px + drift + (rnd() - 0.5) * 2.0);
			var o = px + (rnd() - 0.5) * 0.6;
			var c = px + (rnd() - 0.5) * 0.6;
			var h = Math.max(o, c) + rnd() * 0.9;
			var l = Math.min(o, c) - rnd() * 0.9;
			bars.push({ open: o, high: h, low: l, close: c, volume: 1000.0 + rnd() * 900.0,
				time: (i : Float), index: i });
		}
		return bars;
	}

	/** Same convention as IndicatorTapeBench.synthArgs, so both tools drive indicators alike. */
	static function synthArgs(spec:IndicatorSpec):Array<Dynamic> {
		var windowIdx = 0;
		return [for (t in spec.args) {
			switch (t) {
				case TSeries: ("close" : Dynamic);
				case TWindow: { windowIdx++; ((5 * windowIdx : Float) : Dynamic); }
				case TString: ("x" : Dynamic);
				default: (0.5 : Dynamic);
			}
		}];
	}

	/**
	 * Full precision, stable for NaN/Infinity, and ALWAYS single-line.
	 *
	 * Many indicators return a structure (bands, pivots, zones...). `Std.string` pretty-prints
	 * those across multiple lines, which would destroy the one-line-per-indicator diff
	 * granularity this file exists for — so structures go through `Json.stringify`, and
	 * numbers are handled first so the non-finite cases stay readable (Json emits `null` for
	 * NaN/Infinity, which would silently collapse three distinct values into one).
	 */
	static function fmt(v:Dynamic):String {
		if (v == null) return "null";
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
			var f:Float = cast v;
			if (Math.isNaN(f)) return "NaN";
			if (f == Math.POSITIVE_INFINITY) return "+Inf";
			if (f == Math.NEGATIVE_INFINITY) return "-Inf";
			return Std.string(f);
		}
		if (Std.isOfType(v, String) || Std.isOfType(v, Bool)) return Std.string(v);
		return try haxe.Json.stringify(v) catch (_:Dynamic) StringTools.replace(Std.string(v), "\n", " ");
	}

	public static function main():Void {
		var bars = tape(BARS, SEED);
		var specs:Array<IndicatorSpec> = [for (_ => s in IndicatorRegistry.all()) s];
		specs.sort((a, b) -> Reflect.compare(a.name, b.name));

		Sys.println('# indicator golden snapshot — ${specs.length} indicators x ${bars.length} bars, seed $SEED');
		for (spec in specs) {
			var args = synthArgs(spec);
			var h = new HarnessContext();
			var out = new StringBuf();
			var status = "ok";
			try {
				for (bar in bars) {
					h.observeBar(bar);
					out.add(fmt(spec.eval(h, args)));
					out.add(" ");
				}
			} catch (e:Dynamic) {
				status = "ERR:" + Std.string(e);
			}
			// One line per indicator: name, status, then every per-bar value. Diff granularity
			// is therefore "which indicator changed", which is exactly the unit of the migration.
			Sys.println(spec.name + "\t" + status + "\t" + out.toString());
		}
	}
}
