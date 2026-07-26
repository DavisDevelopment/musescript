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
 * Batch change-point validator stub — run offline over a finished series.
 * Returns candidate break indices (empty until a real CPD backend is wired).
 */
class CpdValidator {
	public static function detectBreaks(series:Array<Float>, minSeg:Int = 20):Array<Int> {
		// Stub: variance-ratio heuristic placeholder — returns empty if too short.
		if (series == null || series.length < minSeg * 2) return [];
		var breaks:Array<Int> = [];
		// Intentionally conservative stub — real CPD (PELT/BOCPD) belongs offline.
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
		var first = closes[0];
		var last = closes[n - 1];
		var mid = closes[Std.int(n / 2)];
		var accel = (last - mid) - (mid - first);
		var warning = last > first && accel > 0;
		return {
			warning: warning,
			tc: n * 1.0 + 5.0,
			residual: Math.abs(accel),
			message: warning ? "LPPL heuristic warning — offline BubbleRisk only" : "no warning"
		};
	}
}
