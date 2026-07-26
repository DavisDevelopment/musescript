package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.geom.SwingGraph;

/** One ranked Elliott hypothesis over a pivot window. */
typedef EwHypothesis = {
	var rank:Int;
	var score:Float;
	var label:String; // "impulse5" | "zigzag" | "unknown"
	var startBar:Int;
	var endBar:Int;
	var waveCount:Int;
}

/**
 * Top-K hypothesis lattice over a SwingGraph.
 * Hard rules gate admission; SoftScores multiply the base rank score (Fib/time/length).
 * Soft scores (volume/Hurst/CPD) can still multiply `score` externally.
 */
class EwLattice {
	static inline var MAX_K = 8;

	var hypotheses:haxe.ds.Vector<EwHypothesis>;
	var count:Int;
	var pivotScratch:haxe.ds.Vector<PivotPoint>;

	public function new() {
		hypotheses = new haxe.ds.Vector<EwHypothesis>(MAX_K);
		for (i in 0...MAX_K) {
			hypotheses[i] = {
				rank: i, score: 0.0, label: "unknown",
				startBar: -1, endBar: -1, waveCount: 0
			};
		}
		pivotScratch = new haxe.ds.Vector<PivotPoint>(16);
		count = 0;
	}

	public function hypothesisCount():Int return count;
	public inline function at(i:Int):EwHypothesis return hypotheses[i];

	public function rebuild(g:SwingGraph, k:Int = 3):Int {
		count = 0;
		var n = g.pivotCount();
		if (n < 4) return 0;
		var take = n < pivotScratch.length ? n : pivotScratch.length;
		for (i in 0...take) pivotScratch[i] = g.pivotAt(n - take + i);

		// Scan for zigzag (4 pivots) and five-wave (6 pivots)
		if (take >= 4) {
			var o = take - 4;
			var p0 = pivotScratch[o];
			var p1 = pivotScratch[o + 1];
			var p2 = pivotScratch[o + 2];
			var p3 = pivotScratch[o + 3];
			if (CorrectiveRules.isValidZigzag(p0, p1, p2, p3)) {
				var soft = CorrectiveRules.softScore(p0, p1, p2, p3);
				push({
					rank: 0, score: 1.0 * soft, label: "zigzag",
					startBar: p0.bar, endBar: p3.bar, waveCount: 3
				}, k);
			}
		}
		if (take >= 6) {
			var o = take - 6;
			if (ImpulseRules.isValidFiveWave(pivotScratch, o)) {
				var soft = ImpulseRules.softScoreFiveWave(pivotScratch, o);
				push({
					rank: 0, score: 1.2 * soft, label: "impulse5",
					startBar: pivotScratch[o].bar, endBar: pivotScratch[o + 5].bar, waveCount: 5
				}, k);
			}
		}
		// Sort by score desc (tiny k — insertion)
		for (i in 1...count) {
			var key = hypotheses[i];
			var j = i - 1;
			while (j >= 0 && hypotheses[j].score < key.score) {
				hypotheses[j + 1] = hypotheses[j];
				j--;
			}
			hypotheses[j + 1] = key;
		}
		for (i in 0...count) hypotheses[i].rank = i;
		return count;
	}

	function push(h:EwHypothesis, k:Int):Void {
		if (count >= k || count >= MAX_K) {
			// Replace weakest if better
			var worst = 0;
			for (i in 1...count) if (hypotheses[i].score < hypotheses[worst].score) worst = i;
			if (h.score <= hypotheses[worst].score) return;
			hypotheses[worst] = h;
			return;
		}
		hypotheses[count++] = h;
	}
}
