package musescript.evo.nma;

import musescript.harness.Bar;
import musescript.indicators.GrowableVec;

/**
 * Semantic-RDO helpers: desired per-bar boolean targets + Hamming distance over NMA `lastSeries`
 * columns (0/1). Desired long = forward close return over `horizon` bars exceeds cost threshold.
 *
 * «Σεμέλης παῖς· λύσις δεσμῶν.»
 */
class NmaSemantic {
	public static inline var DEFAULT_HORIZON = 5;

	/**
	 * Per-bar target: 1 if `(close[i+h]-close[i])/close[i] > costBps*1e-4`, else 0.
	 * Last `horizon` bars are 0 (no forward window).
	 *
	 * «ὄργια νυκτός· θέμις ἄγει.»
	 */
	public static function desiredLong(bars:Array<Bar>, horizon:Int, costBps:Float):GrowableVec<Float> {
		var n = bars.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var thr = costBps * 1e-4;
		for (i in 0...n) {
			if (i + horizon >= n) { col.push(0.0); continue; }
			var c0 = bars[i].close;
			var c1 = bars[i + horizon].close;
			var ret = (c0 != 0) ? (c1 - c0) / c0 : 0.0;
			col.push(ret > thr ? 1.0 : 0.0);
		}
		return col;
	}

	/** Hamming distance / n between two 0/1 columns (mismatch rate in [0,1]). */
	public static function hammingRate(a:GrowableVec<Float>, b:GrowableVec<Float>):Float {
		var n = Std.int(Math.min(a.length, b.length));
		if (n <= 0) return 1.0;
		var mism = 0;
		for (i in 0...n) {
			var xa = a.at(i) >= 0.5;
			var xb = b.at(i) >= 0.5;
			if (xa != xb) mism++;
		}
		return mism / n;
	}
}
