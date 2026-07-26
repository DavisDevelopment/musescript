package musescript.indicators.offline;

/**
 * Offline-only hooks. NEVER call from MuseIndicator.update.
 *
 * - CPD: change-point detection validator (batch)
 * - LpplFit: bubble-risk LPPL fit (separate from EwProject)
 * - FeatureDump: export geometry/EW soft features for offline AI / DRL
 */

typedef FeatureDumpRow = {
	var bar:Int;
	var close:Float;
	var swingDir:Float;
	var fib618:Float;
	var ewLabelCode:Float;
	var hurst:Float;
	var scaleGate:Float;
}

class FeatureDump {
	var rows:Array<FeatureDumpRow>;

	public function new() {
		rows = [];
	}

	public function push(row:FeatureDumpRow):Void {
		rows.push(row);
	}

	public function toArray():Array<FeatureDumpRow> return rows;

	public function clear():Void rows = [];
}

/**
 * Batch change-point validator — offline only.
 * Lightweight two-window mean-shift scan (not PELT/BOCPD). Conservative thresholds.
 */
class CpdValidator {
	public static function detectBreaks(series:Array<Float>, minSeg:Int = 20):Array<Int> {
		if (series == null || series.length < minSeg * 2) return [];
		var breaks:Array<Int> = [];
		var n = series.length;
		var w = minSeg;
		var i = w;
		while (i + w < n) {
			var mL = 0.0;
			var mR = 0.0;
			var vL = 0.0;
			var vR = 0.0;
			for (k in 0...w) {
				mL += series[i - w + k];
				mR += series[i + k];
			}
			mL /= w;
			mR /= w;
			for (k in 0...w) {
				var a = series[i - w + k] - mL;
				var b = series[i + k] - mR;
				vL += a * a;
				vR += b * b;
			}
			vL /= w;
			vR /= w;
			var pooled = Math.sqrt((vL + vR) * 0.5) + 1e-12;
			var z = Math.abs(mR - mL) / pooled;
			// Conservative: require ~2σ mean shift and skip nearby duplicates
			if (z >= 2.0) {
				if (breaks.length == 0 || i - breaks[breaks.length - 1] >= w) {
					breaks.push(i);
				}
			}
			i += Std.int(w / 2);
			if (i <= 0) break;
		}
		return breaks;
	}
}

/**
 * LPPL bubble-risk batch fit — WARNING ONLY, never inside EwProject / indicators.
 */
typedef LpplFitResult = {
	var warning:Bool;
	var tc:Float;
	var residual:Float;
	var message:String;
}

class LpplFit {
	/**
	 * Extremely rough heuristic: accelerating rise + rising volatility → warning.
	 * Not a real LPPL MLE — placeholder for offline BubbleRisk tooling.
	 */
	public static function fitWarning(closes:Array<Float>):LpplFitResult {
		if (closes == null || closes.length < 30) {
			return { warning: false, tc: Math.NaN, residual: Math.NaN, message: "insufficient data" };
		}
		var n = closes.length;
		var vec = new haxe.ds.Vector<Float>(n);
		for (i in 0...n) vec[i] = closes[i];
		return fitWarningVec(vec, n);
	}

	/** Vector form — preferred by streaming facades (no Array alloc). */
	public static function fitWarningVec(closes:haxe.ds.Vector<Float>, n:Int):LpplFitResult {
		if (closes == null || n < 30) {
			return { warning: false, tc: Math.NaN, residual: Math.NaN, message: "insufficient data" };
		}
		var first = closes[0];
		var last = closes[n - 1];
		var mid = closes[Std.int(n / 2)];
		var accel = (last - mid) - (mid - first);
		// Second half vol vs first half vol
		var v1 = 0.0;
		var v2 = 0.0;
		var half = Std.int(n / 2);
		for (i in 1...half) {
			var d = closes[i] - closes[i - 1];
			v1 += d * d;
		}
		for (i in half + 1...n) {
			var d = closes[i] - closes[i - 1];
			v2 += d * d;
		}
		v1 /= Math.max(1, half - 1);
		v2 /= Math.max(1, n - half - 1);
		var volRise = v2 > v1 * 1.15;
		var warning = last > first && accel > 0 && volRise;
		var residual = Math.abs(accel) + Math.abs(v2 - v1);
		return {
			warning: warning,
			tc: n * 1.0 + 5.0,
			residual: residual,
			message: warning ? "LPPL heuristic warning — offline BubbleRisk only" : "no warning"
		};
	}
}
