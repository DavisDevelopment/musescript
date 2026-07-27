package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.SwingGraphStack;
import musescript.indicators.geom.SoftScores;

/**
 * Top-K hypothesis lattice — multi-window scan (Ch1: multiple valid counts).
 * Hard rules gate; SoftScores × EwGuidelines × EwPhiParams rank.
 * `rebuildStack` scans fine + coarse graphs and soft-ranks nested fits (Ch2 depth).
 */
class EwLattice {
	static inline var MAX_K = 8;
	static inline var SCRATCH = 32;

	static function makeHyp(
		label:String, score:Float, startBar:Int, endBar:Int,
		waveCount:Int, degree:Int, offset:Int
	):EwHypothesis {
		return {
			rank: 0, score: score, label: label,
			startBar: startBar, endBar: endBar, waveCount: waveCount, degree: degree, offset: offset,
			parentHypothesisId: -1, parentStartBar: -1, parentEndBar: -1, nestScore: 1.0
		};
	}

	var hypotheses:haxe.ds.Vector<EwHypothesis>;
	var count:Int;
	var pivotScratch:haxe.ds.Vector<PivotPoint>;
	var coarseScratch:haxe.ds.Vector<PivotPoint>;
	var coarseHypotheses:haxe.ds.Vector<EwHypothesis>;
	var coarseCount:Int;
	var params:EwPhiParams;
	var useGuidelines:Bool;

	public function new(?params:EwPhiParams, useGuidelines:Bool = true) {
		this.params = params != null ? params : EwPhiParams.current();
		this.useGuidelines = useGuidelines;
		hypotheses = new haxe.ds.Vector<EwHypothesis>(MAX_K);
		coarseHypotheses = new haxe.ds.Vector<EwHypothesis>(MAX_K);
		for (i in 0...MAX_K) {
			hypotheses[i] = makeHyp("unknown", 0.0, -1, -1, 0, 0, 0);
			hypotheses[i].rank = i;
			coarseHypotheses[i] = makeHyp("unknown", 0.0, -1, -1, 0, 1, 0);
			coarseHypotheses[i].rank = i;
		}
		pivotScratch = new haxe.ds.Vector<PivotPoint>(SCRATCH);
		coarseScratch = new haxe.ds.Vector<PivotPoint>(SCRATCH);
		count = 0;
		coarseCount = 0;
	}

	public function hypothesisCount():Int return count;
	public function coarseHypothesisCount():Int return coarseCount;
	public inline function at(i:Int):EwHypothesis return hypotheses[i];
	public inline function coarseAt(i:Int):EwHypothesis return coarseHypotheses[i];
	public inline function scratch():haxe.ds.Vector<PivotPoint> return pivotScratch;
	public inline function coarseScratchVec():haxe.ds.Vector<PivotPoint> return coarseScratch;
	public inline function scratchLen():Int {
		var n = 0;
		// length filled on last rebuild — store in field
		return scratchFilled;
	}
	var scratchFilled:Int = 0;
	var coarseScratchFilled:Int = 0;

	public function rebuild(g:SwingGraph, k:Int = 3, degree:Int = 0):Int {
		coarseCount = 0;
		count = scanInto(g, pivotScratch, hypotheses, degree, k, true);
		scratchFilled = filledLen;
		return count;
	}

	/**
	 * Fine + coarse stack: degree-0 windows on fine graph, degree-1 on coarse,
	 * then soft-multiply fine scores by nesting fit vs best coarse parent.
	 */
	public function rebuildStack(stack:SwingGraphStack, k:Int = 3):Int {
		count = scanInto(stack.fine, pivotScratch, hypotheses, 0, k, false);
		scratchFilled = filledLen;
		coarseCount = scanInto(stack.coarse, coarseScratch, coarseHypotheses, 1, k, false);
		coarseScratchFilled = filledLen;

		for (i in 0...count) {
			var h = hypotheses[i];
			var best = bestParentFor(h);
			if (best >= 0) {
				var parent = coarseHypotheses[best];
				h.parentHypothesisId = best;
				h.parentStartBar = parent.startBar;
				h.parentEndBar = parent.endBar;
				h.nestScore = nestingSoft(h, parent, pivotScratch, coarseScratch);
				h.score *= h.nestScore;
			} else {
				h.parentHypothesisId = -1;
				h.parentStartBar = -1;
				h.parentEndBar = -1;
				h.nestScore = 1.0;
			}
		}
		sortRank(hypotheses, count);
		return count;
	}

	var filledLen:Int = 0;

	function scanInto(g:SwingGraph, buf:haxe.ds.Vector<PivotPoint>, out:haxe.ds.Vector<EwHypothesis>,
		degree:Int, k:Int, sortAfter:Bool):Int {
		var cnt = 0;
		var n = g.pivotCount();
		if (n < 4) {
			filledLen = 0;
			return 0;
		}
		var take = n < SCRATCH ? n : SCRATCH;
		filledLen = take;
		for (i in 0...take) buf[i] = g.pivotAt(n - take + i);

		var limK = k < 1 ? 1 : (k > MAX_K ? MAX_K : k);

		var maxO4 = take - 4;
		for (o in 0...maxO4 + 1) {
			var a = buf[o];
			var b = buf[o + 1];
			var c = buf[o + 2];
			var d = buf[o + 3];
			if (CorrectiveRules.isValidZigzag(a, b, c, d, params)) {
				var soft = CorrectiveRules.softScore(a, b, c, d, params);
				var depth = EwGuidelines.depthSoft(Math.abs(c.price - b.price) / Math.max(1e-12, Math.abs(b.price - a.price)), params);
				cnt = pushInto(out, makeHyp("zigzag", soft * depth, a.bar, d.bar, 3, degree, o), cnt, limK);
			}
			var fk = CorrectiveRules.flatKind(a, b, c, d, params);
			if (fk != 0) {
				var softF = CorrectiveRules.softScore(a, b, c, d, params) * (fk == 2 ? 1.0 : 0.95);
				cnt = pushInto(out, makeHyp(CorrectiveRules.flatLabel(fk), softF, a.bar, d.bar, 3, degree, o), cnt, limK);
			}
		}

		if (take >= 6) {
			var maxO6 = take - 6;
			for (o in 0...maxO6 + 1) {
				if (ImpulseRules.isValidFiveWave(buf, o)) {
					var soft = ImpulseRules.softScoreFiveWave(buf, o, params);
					if (useGuidelines) soft *= EwGuidelines.scoreImpulse(buf, o, params);
					cnt = pushInto(out, makeHyp("impulse5", 1.2 * soft, buf[o].bar, buf[o + 5].bar, 5, degree, o), cnt, limK);
				} else if (ImpulseRules.isValidDiagonal(buf, o)) {
					var softD = ImpulseRules.softScoreFiveWave(buf, o, params) * 0.9;
					cnt = pushInto(out, makeHyp("diagonal", softD, buf[o].bar, buf[o + 5].bar, 5, degree, o), cnt, limK);
				}
				if (CorrectiveRules.isValidTriangle(buf, o, params)) {
					var softT = CorrectiveRules.softScoreTriangle(buf, o, params);
					cnt = pushInto(out, makeHyp("triangle", 0.7 * softT, buf[o].bar, buf[o + 5].bar, 5, degree, o), cnt, limK);
				}
			}
		}

		if (take >= 8) {
			var maxO8 = take - 8;
			for (o in 0...maxO8 + 1) {
				if (CorrectiveRules.isValidDoubleZigzag(buf, o, params)) {
					var softW = CorrectiveRules.softScoreDoubleZigzag(buf, o, params);
					cnt = pushInto(out, makeHyp("double_zigzag", 0.85 * softW, buf[o].bar, buf[o + 7].bar, 7, degree, o), cnt, limK);
				}
			}
		}

		if (sortAfter) sortRank(out, cnt);
		return cnt;
	}

	function bestParentFor(child:EwHypothesis):Int {
		if (coarseCount == 0) return -1;
		var best = -1;
		var bestNest = 0.0;
		for (pi in 0...coarseCount) {
			var parent = coarseHypotheses[pi];
			if (child.startBar < parent.startBar || child.endBar > parent.endBar) continue;
			var nest = nestingSoft(child, parent, pivotScratch, coarseScratch);
			if (nest > bestNest) {
				bestNest = nest;
				best = pi;
			}
		}
		return best;
	}

	/**
	 * Ch2 depth guideline: inner corrective prefers parent wave-4 price territory
	 * when parent is an impulse/diagonal; bar containment is a soft multiplier.
	 */
	public static function nestingSoft(child:EwHypothesis, parent:EwHypothesis,
		fineScratch:haxe.ds.Vector<PivotPoint>, coarseScratch:haxe.ds.Vector<PivotPoint>, ?params:EwPhiParams):Float {
		var p = params != null ? params : EwPhiParams.current();
		if (parent == null) return 1.0;

		var barContain = 0.55;
		if (child.startBar >= parent.startBar && child.endBar <= parent.endBar) barContain = 1.0;
		else if (child.startBar <= parent.endBar && child.endBar >= parent.startBar) barContain = 0.75;

		if (child.startBar > parent.endBar || child.endBar < parent.startBar)
			return Math.min(1.0, Math.max(0.35, barContain * p.depthIntoPriorFourth));

		var w4Score = 0.55;
		if (parent.label == "impulse5" || parent.label == "diagonal") {
			var o = parent.offset;
			if (o + 4 < coarseScratch.length) {
				var p3 = coarseScratch[o + 3].price;
				var p4 = coarseScratch[o + 4].price;
				var lo = Math.min(p3, p4);
				var hi = Math.max(p3, p4);
				var childLo = fineScratch[child.offset].price;
				var childHi = childLo;
				var endIdx = child.offset + child.waveCount - 1;
				if (endIdx < fineScratch.length) {
					childHi = fineScratch[endIdx].price;
					if (childHi < childLo) {
						var t = childLo;
						childLo = childHi;
						childHi = t;
					}
				}
				var mid = (childLo + childHi) * 0.5;
				if (mid >= lo && mid <= hi) w4Score = 1.0;
				else {
					var dist = mid < lo ? lo - mid : mid - hi;
					var span = Math.max(1e-12, hi - lo);
					w4Score = Math.max(0.4, 1.0 - dist / span);
				}
			}
		} else if (parent.label == "zigzag" || parent.label == "flat" || parent.label == "flat_expanded" || parent.label == "flat_running") {
			var po = parent.offset;
			if (po + 2 < coarseScratch.length) {
				var a = coarseScratch[po].price;
				var b = coarseScratch[po + 1].price;
				var bLo = Math.min(a, b);
				var bHi = Math.max(a, b);
				var endIdx = child.offset + child.waveCount - 1;
				if (endIdx < fineScratch.length) {
					var mid = (fineScratch[child.offset].price + fineScratch[endIdx].price) * 0.5;
					if (mid >= bLo && mid <= bHi) w4Score = 0.95;
				}
			}
		}

		var raw = SoftScores.combine(barContain, w4Score);
		return Math.min(1.0, Math.max(0.35, raw * p.depthIntoPriorFourth));
	}

	function sortRank(buf:haxe.ds.Vector<EwHypothesis>, cnt:Int):Void {
		if (cnt <= 1) {
			if (cnt == 1) buf[0].rank = 0;
			return;
		}
		for (i in 1...cnt) {
			var key = buf[i];
			var j = i - 1;
			while (j >= 0 && buf[j].score < key.score) {
				buf[j + 1] = buf[j];
				j--;
			}
			buf[j + 1] = key;
		}
		for (i in 0...cnt) buf[i].rank = i;
	}

	function pushInto(buf:haxe.ds.Vector<EwHypothesis>, h:EwHypothesis, cnt:Int, k:Int):Int {
		if (cnt >= k || cnt >= MAX_K) {
			var worst = 0;
			for (i in 1...cnt) if (buf[i].score < buf[worst].score) worst = i;
			if (h.score <= buf[worst].score) return cnt;
			buf[worst] = h;
			return cnt;
		}
		buf[cnt++] = h;
		return cnt;
	}

	function push(h:EwHypothesis, k:Int):Void {
		count = pushInto(hypotheses, h, count, k);
	}
}
