package musescript.indicators.geom;

/** Linear vs log price geometry for project/retrace. */
enum abstract ScaleMode(Int) from Int to Int {
	var Linear = 0;
	var Log = 1;
}

/** Densest cluster among candidate levels. */
typedef ClusterResult = {
	var price:Float;
	var strength:Float;
	var count:Int;
}

/**
 * Shared project / retrace / confluence engine for Fib, harmonics, and EW bands.
 *
 * Price geometry:
 * - Linear retrace from swing high→low: `end + r * (start - end)` with start=high, end=low
 *   for an up-leg retrace, or equivalently `ll + r * (hh - ll)` for a window HH/LL ladder.
 * - Log mode operates in ln-space then exp back (relative moves constant in %).
 *
 * Hot paths: indexed loops only; scratch buffers reused via optional out-params.
 */
class RatioEngine {
	/**
	 * Retrace level between `start` and `end` at ratio `r` (0 = at end, 1 = at start).
	 * Matches AutoFib / GoldenPocket: `end + r * (start - end)`.
	 */
	public static inline function retrace(start:Float, end:Float, r:Float, scale:ScaleMode = Linear):Float {
		if (scale == Log) {
			if (start <= 0 || end <= 0) return Math.NaN;
			var a = Math.log(start);
			var b = Math.log(end);
			return Math.exp(b + r * (a - b));
		}
		return end + r * (start - end);
	}

	/**
	 * Window-style ladder: level at ratio `r` of [ll, hh] with r=0 → ll, r=1 → hh.
	 * Canonical convenience for trailing-window FibRetracement (`mode=Window`).
	 */
	public static inline function windowLevel(ll:Float, hh:Float, r:Float, scale:ScaleMode = Linear):Float {
		return retrace(hh, ll, r, scale);
	}

	/**
	 * Project a measured leg of length `|leg|` from `from` in `direction`
	 * (+1 = up, −1 = down) by multiple `r`.
	 */
	public static inline function project(from:Float, leg:Float, r:Float, direction:Float, scale:ScaleMode = Linear):Float {
		var mag = Math.abs(leg) * r;
		if (scale == Log) {
			if (from <= 0 || mag < 0) return Math.NaN;
			var lnFrom = Math.log(from);
			var lnDelta = Math.log(from + mag) - lnFrom;
			return Math.exp(lnFrom + (direction >= 0 ? lnDelta : -lnDelta));
		}
		return from + direction * mag;
	}

	/**
	 * Project A→B magnitude from C: `c + r * (b - a)` (signed, linear).
	 * Log: operate on ln of absolute prices when all positive.
	 */
	public static inline function projectLeg(a:Float, b:Float, c:Float, r:Float, scale:ScaleMode = Linear):Float {
		if (scale == Log) {
			if (a <= 0 || b <= 0 || c <= 0) return Math.NaN;
			var la = Math.log(a);
			var lb = Math.log(b);
			var lc = Math.log(c);
			return Math.exp(lc + r * (lb - la));
		}
		return c + r * (b - a);
	}

	/**
	 * Fill `out` with retrace levels for each ratio in `ratios`. Indexed writes only.
	 * Returns count written.
	 */
	public static function fillRetrace(start:Float, end:Float, ratios:Array<Float>, out:haxe.ds.Vector<Float>, scale:ScaleMode = Linear):Int {
		var n = ratios.length;
		if (n > out.length) n = out.length;
		for (i in 0...n) out[i] = retrace(start, end, ratios[i], scale);
		return n;
	}

	/**
	 * Densest cluster among `levels[0..count)`. `tolerance` is relative
	 * (fraction of |center|) when > 0; absolute when tolerance < 0 (−abs used).
	 */
	public static function cluster(levels:haxe.ds.Vector<Float>, count:Int, tolerance:Float = 0.03):Null<ClusterResult> {
		if (count <= 0) return null;
		var maxCount = 0;
		var maxTotal = 0.0;
		for (i in 0...count) {
			var center = levels[i];
			if (!Math.isFinite(center)) continue;
			var members = 0;
			var sum = 0.0;
			var tol = tolerance >= 0
				? Math.abs(center) * tolerance
				: -tolerance;
			if (tol < 1e-12) tol = 1e-12;
			for (j in 0...count) {
				var x = levels[j];
				if (!Math.isFinite(x)) continue;
				if (Math.abs(x - center) <= tol) {
					members++;
					sum += x;
				}
			}
			if (members > maxCount) {
				maxCount = members;
				maxTotal = sum;
			}
		}
		if (maxCount == 0) return null;
		return {
			price: maxTotal / maxCount,
			strength: maxCount * 1.0,
			count: maxCount
		};
	}

	/** Convenience over Array (materializes a temp Vector). Prefer Vector overload on hot path. */
	public static function clusterArray(levels:Array<Float>, tolerance:Float = 0.03):Null<ClusterResult> {
		var n = levels.length;
		var v = new haxe.ds.Vector<Float>(n);
		for (i in 0...n) v[i] = levels[i];
		return cluster(v, n, tolerance);
	}
}
