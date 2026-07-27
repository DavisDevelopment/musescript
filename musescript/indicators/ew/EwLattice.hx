package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Top-K hypothesis lattice — multi-window scan (Ch1: multiple valid counts).
 * Hard rules gate; SoftScores × EwGuidelines × EwPhiParams rank.
 */
class EwLattice {
	static inline var MAX_K = 8;
	static inline var SCRATCH = 32;

	var hypotheses:haxe.ds.Vector<EwHypothesis>;
	var count:Int;
	var pivotScratch:haxe.ds.Vector<PivotPoint>;
	var params:EwPhiParams;
	var useGuidelines:Bool;

	public function new(?params:EwPhiParams, useGuidelines:Bool = true) {
		this.params = params != null ? params : EwPhiParams.current();
		this.useGuidelines = useGuidelines;
		hypotheses = new haxe.ds.Vector<EwHypothesis>(MAX_K);
		for (i in 0...MAX_K) {
			hypotheses[i] = {
				rank: i, score: 0.0, label: "unknown",
				startBar: -1, endBar: -1, waveCount: 0, degree: 0, offset: 0
			};
		}
		pivotScratch = new haxe.ds.Vector<PivotPoint>(SCRATCH);
		count = 0;
	}

	public function hypothesisCount():Int return count;
	public inline function at(i:Int):EwHypothesis return hypotheses[i];
	public inline function scratch():haxe.ds.Vector<PivotPoint> return pivotScratch;
	public inline function scratchLen():Int {
		var n = 0;
		// length filled on last rebuild — store in field
		return scratchFilled;
	}
	var scratchFilled:Int = 0;

	public function rebuild(g:SwingGraph, k:Int = 3, degree:Int = 0):Int {
		count = 0;
		var n = g.pivotCount();
		if (n < 4) {
			scratchFilled = 0;
			return 0;
		}
		var take = n < SCRATCH ? n : SCRATCH;
		scratchFilled = take;
		for (i in 0...take) pivotScratch[i] = g.pivotAt(n - take + i);

		var limK = k < 1 ? 1 : (k > MAX_K ? MAX_K : k);

		// Sliding windows of 4 → zigzag / flat
		var maxO4 = take - 4;
		for (o in 0...maxO4 + 1) {
			var a = pivotScratch[o];
			var b = pivotScratch[o + 1];
			var c = pivotScratch[o + 2];
			var d = pivotScratch[o + 3];
			if (CorrectiveRules.isValidZigzag(a, b, c, d, params)) {
				var soft = CorrectiveRules.softScore(a, b, c, d, params);
				var depth = EwGuidelines.depthSoft(Math.abs(c.price - b.price) / Math.max(1e-12, Math.abs(b.price - a.price)), params);
				push({
					rank: 0, score: soft * depth, label: "zigzag",
					startBar: a.bar, endBar: d.bar, waveCount: 3, degree: degree, offset: o
				}, limK);
			}
			if (CorrectiveRules.isValidFlat(a, b, c, d, params)) {
				var softF = CorrectiveRules.softScore(a, b, c, d, params) * 0.95;
				push({
					rank: 0, score: softF, label: "flat",
					startBar: a.bar, endBar: d.bar, waveCount: 3, degree: degree, offset: o
				}, limK);
			}
		}

		// Sliding windows of 6 → impulse / diagonal / triangle stub
		if (take >= 6) {
			var maxO6 = take - 6;
			for (o in 0...maxO6 + 1) {
				if (ImpulseRules.isValidFiveWave(pivotScratch, o)) {
					var soft = ImpulseRules.softScoreFiveWave(pivotScratch, o, params);
					if (useGuidelines) soft *= EwGuidelines.scoreImpulse(pivotScratch, o, params);
					push({
						rank: 0, score: 1.2 * soft, label: "impulse5",
						startBar: pivotScratch[o].bar, endBar: pivotScratch[o + 5].bar,
						waveCount: 5, degree: degree, offset: o
					}, limK);
				} else if (ImpulseRules.isValidDiagonal(pivotScratch, o)) {
					var softD = ImpulseRules.softScoreFiveWave(pivotScratch, o, params) * 0.9;
					push({
						rank: 0, score: softD, label: "diagonal",
						startBar: pivotScratch[o].bar, endBar: pivotScratch[o + 5].bar,
						waveCount: 5, degree: degree, offset: o
					}, limK);
				}
				if (CorrectiveRules.isValidTriangleStub(pivotScratch, o)) {
					push({
						rank: 0, score: 0.55, label: "triangle",
						startBar: pivotScratch[o].bar, endBar: pivotScratch[o + 5].bar,
						waveCount: 5, degree: degree, offset: o
					}, limK);
				}
			}
		}

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
			var worst = 0;
			for (i in 1...count) if (hypotheses[i].score < hypotheses[worst].score) worst = i;
			if (h.score <= hypotheses[worst].score) return;
			hypotheses[worst] = h;
			return;
		}
		hypotheses[count++] = h;
	}
}
