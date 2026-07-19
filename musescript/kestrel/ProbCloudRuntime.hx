package musescript.kestrel;

/**
 * Pure-Haxe, dependency-free port of the Python `ProbabilityCloud` query API
 * (kalshi-ai-advisor/python/synth/marketsim/unified_diffmarketsim/probability_cloud.py).
 *
 * DELIBERATELY portable: this is the SAME source compiled to JS (web/mobile)
 * and Python (backtest/CLI target) — querying an already-fitted cloud must
 * behave identically everywhere a MuseScript strategy runs, so the math
 * lives here once instead of being reimplemented per platform. FITTING a
 * cloud (the expensive step — encoder pretraining, a real market
 * simulation) stays Python-only (`tools/kestrel_bridge.py`) and produces
 * the portable JSON `fromJson` parses; this class does none of that heavy
 * lifting, only piecewise-linear interpolation over an already-fitted
 * quantile grid — the same interpolation `ProbabilityCloud` does with
 * `np.interp`, ported instruction-for-instruction (see `interp`).
 *
 * JSON shape (matches `ProbabilityCloud.to_dict`-adjacent serialization,
 * NOT `to_dict` itself — that's a rounded display summary; this wants the
 * raw fan):
 * `{ symbols: string[], quantiles: number[], paths: number[][][] /
 * [symbol][quantile][horizonStep] /, horizon: int, coverage:
 * {cov90:number, cov50:number} | null }`.
 */
class ProbCloudRuntime {
	public var symbols(default, null):Array<String>;
	public var quantiles(default, null):Array<Float>;
	/** `[symbolIndex][quantileIndex][horizonStep]`, quantile axis ascending and monotone per column. */
	public var paths(default, null):Array<Array<Array<Float>>>;
	public var horizon(default, null):Int;
	public var coverage(default, null):Null<{cov90:Float, cov50:Float}>;
	var symIndex:Map<String, Int>;

	function new(symbols:Array<String>, quantiles:Array<Float>, paths:Array<Array<Array<Float>>>,
			horizon:Int, coverage:Null<{cov90:Float, cov50:Float}>) {
		this.symbols = symbols;
		this.quantiles = quantiles;
		this.paths = paths;
		this.horizon = horizon;
		this.coverage = coverage;
		this.symIndex = new Map();
		for (i in 0...symbols.length) this.symIndex.set(symbols[i], i);
	}

	public static function fromJson(value:Dynamic):ProbCloudRuntime {
		if (value == null) throw "ProbCloud: null value";
		var rawSymbols:Array<Dynamic> = Reflect.field(value, "symbols");
		var rawQuantiles:Array<Dynamic> = Reflect.field(value, "quantiles");
		var rawPaths:Array<Dynamic> = Reflect.field(value, "paths");
		var horizonField = Reflect.field(value, "horizon");
		if (rawSymbols == null || rawQuantiles == null || rawPaths == null || horizonField == null)
			throw "ProbCloud: missing symbols/quantiles/paths/horizon";
		var horizon:Int = Std.int(horizonField);
		var symbols:Array<String> = [for (s in rawSymbols) Std.string(s)];
		if (symbols.length != rawPaths.length)
			throw 'ProbCloud: ${symbols.length} symbols but ${rawPaths.length} path rows';

		// Canonicalize quantile order (ascending) — mirrors Python's
		// `from_projection`'s `order = np.argsort(q)` step.
		var qi = [for (i in 0...rawQuantiles.length) i];
		qi.sort((a, b) -> {
			var qa:Float = rawQuantiles[a];
			var qb:Float = rawQuantiles[b];
			return qa < qb ? -1 : (qa > qb ? 1 : 0);
		});
		var quantiles:Array<Float> = [for (i in qi) (rawQuantiles[i] : Float)];

		var paths:Array<Array<Array<Float>>> = [];
		for (si in 0...symbols.length) {
			var symPaths:Array<Dynamic> = rawPaths[si];
			if (symPaths.length != rawQuantiles.length)
				throw 'ProbCloud: symbol ${symbols[si]} has ${symPaths.length} quantile rows, expected ${rawQuantiles.length}';
			var reordered:Array<Array<Float>> = [for (i in qi) {
				var row:Array<Dynamic> = symPaths[i];
				[for (v in row) (v : Float)];
			}];
			// Defensive: monotone in level per horizon column — mirrors
			// Python's `np.sort(paths, axis=1)` step.
			paths.push(sortColumnsMonotone(reordered));
		}

		var coverage:Null<{cov90:Float, cov50:Float}> = null;
		var covRaw = Reflect.field(value, "coverage");
		if (covRaw != null)
			coverage = {cov90: Reflect.field(covRaw, "cov90"), cov50: Reflect.field(covRaw, "cov50")};

		return new ProbCloudRuntime(symbols, quantiles, paths, horizon, coverage);
	}

	static function sortColumnsMonotone(rows:Array<Array<Float>>):Array<Array<Float>> {
		if (rows.length == 0) return rows;
		var h = rows[0].length;
		var out:Array<Array<Float>> = [for (_ in rows) []];
		for (col in 0...h) {
			var vals = [for (r in rows) r[col]];
			vals.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			for (qi in 0...rows.length) out[qi].push(vals[qi]);
		}
		return out;
	}

	function symIdx(symbol:String):Int {
		var i = symIndex.get(symbol);
		if (i == null) throw 'ProbCloud: unknown symbol $symbol';
		return i;
	}

	/** Python's `h` is an index into the horizon axis; -1 means the terminal step. */
	function hIdx(h:Int):Int {
		return h < 0 ? horizon + h : h;
	}

	/**
	 * Piecewise-linear interpolation matching `numpy.interp`: `xp` must be
	 * non-decreasing; clamps to the boundary `fp` values outside
	 * `[xp[0], xp[last]]` (never extrapolates) — this, not a full spline, is
	 * exactly what keeps `ProbabilityCloud`'s tail probabilities from ever
	 * reading as overconfident 0/1 (see the Python docstring). Binary search
	 * for the bracketing pair, matching `np.interp`'s behavior on a
	 * monotone `xp` (ties resolve to the LOWER bracket, same as numpy).
	 */
	public static function interp(x:Float, xp:Array<Float>, fp:Array<Float>):Float {
		var n = xp.length;
		if (n == 0) return Math.NaN;
		if (n == 1) return fp[0];
		if (x <= xp[0]) return fp[0];
		if (x >= xp[n - 1]) return fp[n - 1];
		var lo = 0, hi = n - 1;
		while (hi - lo > 1) {
			var mid = (lo + hi) >> 1;
			if (xp[mid] <= x) lo = mid; else hi = mid;
		}
		var x0 = xp[lo], x1 = xp[hi], y0 = fp[lo], y1 = fp[hi];
		if (x1 == x0) return y0;
		return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
	}

	// ── central tendency & dispersion (per symbol) ─────────────────────────

	public function median(symbol:String, h:Int = -1):Float {
		var si = symIdx(symbol);
		var hi = hIdx(h);
		var mi = 0;
		var best = Math.POSITIVE_INFINITY;
		for (i in 0...quantiles.length) {
			var d = Math.abs(quantiles[i] - 0.5);
			if (d < best) { best = d; mi = i; }
		}
		return paths[si][mi][hi];
	}

	public function quantileAt(symbol:String, level:Float, h:Int = -1):Float {
		var si = symIdx(symbol);
		var hi = hIdx(h);
		var vals = [for (qi in 0...quantiles.length) paths[si][qi][hi]];
		return interp(level, quantiles, vals);
	}

	public function intervalLow(symbol:String, coverage:Float = 0.9, h:Int = -1):Float {
		var a = (1.0 - coverage) / 2.0;
		return quantileAt(symbol, a, h);
	}

	public function intervalHigh(symbol:String, coverage:Float = 0.9, h:Int = -1):Float {
		var a = (1.0 - coverage) / 2.0;
		return quantileAt(symbol, 1.0 - a, h);
	}

	public function iqr(symbol:String, h:Int = -1):Float {
		return intervalHigh(symbol, 0.5, h) - intervalLow(symbol, 0.5, h);
	}

	public function width(symbol:String, coverage:Float = 0.9, h:Int = -1):Float {
		return intervalHigh(symbol, coverage, h) - intervalLow(symbol, coverage, h);
	}

	/** Cross-sectional inverse-width in [0,1]: 1 = tightest fan in the WHOLE
	 * panel (most certain), matching Python's `conviction` exactly —
	 * genuinely panel-wide, not a per-symbol-only computation. */
	public function conviction(symbol:String, h:Int = -1):Float {
		var widths = [for (s in symbols) width(s, 0.9, h)];
		var lo = widths[0], hiV = widths[0];
		for (w in widths) {
			if (w < lo) lo = w;
			if (w > hiV) hiV = w;
		}
		if (hiV - lo < 1e-12) return 0.5;
		var w = width(symbol, 0.9, h);
		return 1.0 - (w - lo) / (hiV - lo);
	}

	/** Bowley (quantile) skewness in [-1,1] from the 5/50/95 levels. */
	public function skew(symbol:String, h:Int = -1):Float {
		var lo = intervalLow(symbol, 0.9, h);
		var hiV = intervalHigh(symbol, 0.9, h);
		var med = median(symbol, h);
		var denom = hiV - lo;
		if (Math.abs(denom) < 1e-12) denom = 1e-12;
		var sk = (hiV + lo - 2.0 * med) / denom;
		return sk < -1.0 ? -1.0 : (sk > 1.0 ? 1.0 : sk);
	}

	/** E[X] via the quantile function integral: trapezoid on Q(p) over the
	 * fitted grid plus flat-tail masses outside it — matches Python's
	 * `expected_value` (there via `np.trapezoid`) term for term. */
	public function expectedValue(symbol:String, h:Int = -1):Float {
		var si = symIdx(symbol);
		var hi = hIdx(h);
		var vals = [for (qi in 0...quantiles.length) paths[si][qi][hi]];
		var body = 0.0;
		for (i in 0...quantiles.length - 1) {
			var dq = quantiles[i + 1] - quantiles[i];
			body += (vals[i] + vals[i + 1]) / 2.0 * dq;
		}
		var last = quantiles.length - 1;
		var tail = quantiles[0] * vals[0] + (1.0 - quantiles[last]) * vals[last];
		return body + tail;
	}

	// ── probabilities (the decision surface) ───────────────────────────────

	/** P(X <= x) via piecewise-linear inverse of the quantile grid — flat-
	 * clamped at the outer quantiles, so this never reads as exactly 0/1. */
	public function cdf(symbol:String, x:Float, h:Int = -1):Float {
		var si = symIdx(symbol);
		var hi = hIdx(h);
		var vals = [for (qi in 0...quantiles.length) paths[si][qi][hi]];
		return interp(x, vals, quantiles);
	}

	public function probBelow(symbol:String, x:Float, h:Int = -1):Float
		return cdf(symbol, x, h);

	public function probAbove(symbol:String, x:Float, h:Int = -1):Float
		return 1.0 - cdf(symbol, x, h);

	public function probBetween(symbol:String, a:Float, b:Float, h:Int = -1):Float {
		var lo = a < b ? a : b;
		var hiV = a < b ? b : a;
		var out = cdf(symbol, hiV, h) - cdf(symbol, lo, h);
		return out < 0.0 ? 0.0 : (out > 1.0 ? 1.0 : out);
	}

	/** P(X > 0) — the directional edge (target channel is a standardized return). */
	public function probUp(symbol:String, h:Int = -1):Float
		return probAbove(symbol, 0.0, h);

	// ── calibration honesty ─────────────────────────────────────────────────

	public function isCalibrated():Bool
		return coverage != null;

	public function trustNote():String {
		if (coverage == null) return "uncalibrated (treat probabilities as ordinal, not literal)";
		return 'calibrated (held-out cov90=${round2(coverage.cov90)} / cov50=${round2(coverage.cov50)}; nominal .90/.50)';
	}

	static function round2(v:Float):String {
		var r = Math.round(v * 100) / 100;
		return Std.string(r);
	}
}
