package musescript.indicators.ew;

import musescript.indicators.geom.SoftScores;

/**
 * Named φ / guideline / ratio weights for Elliott Wave soft scoring and targets.
 *
 * HARD structural rules never read these floats for boolean gates.
 * Soft scores, projections, and offline finetune dumps do.
 *
 * Defaults = Frost & Prechter / EWI course handbook tendencies (Ch3–4).
 * Load a finetuned pack later without changing rule code.
 *
 * Louisli-style `p * ((1±pe)**r)` chains map to these named targets + smooth hits.
 */
class EwPhiParams {
	// --- Core φ family (Ch3) ---
	public var phi:Float;
	public var phiInv:Float; // 0.618…
	public var phiSq:Float; // 2.618…
	public var oneMinusPhiInv:Float; // 0.382
	public var half:Float;
	public var sqrtPhiInvApprox:Float; // 0.786 ≈ √φ⁻¹-ish textbook band
	public var phiExt1272:Float; // 1.272
	public var phiExt1618:Float;
	public var phiExt2618:Float;
	public var phiExt4236:Float;

	// --- Soft-hit tolerances ---
	public var fibHitTol:Float;
	public var timeHitTol:Float;
	public var equalityTol:Float;

	// --- Ch1 corrective soft bands ---
	/** Zigzag B retrace of A must be in (zigzagBMin, zigzagBMax]. */
	public var zigzagBMin:Float;
	public var zigzagBMax:Float;
	/** Zigzag C vs A minimum length ratio (hard floor stays in CorrectiveRules). */
	public var zigzagCMinVsA:Float;

	/** Regular flat: |B|/|A| near this (soft). */
	public var flatBNear:Float;
	/** Expanded flat: B beyond start of A by at least this fraction of |A|. */
	public var flatBBeyond:Float;
	/** Flat C vs A typical multiple soft targets. */
	public var flatCVsA:Float;

	// --- Ch2 guidelines ---
	public var alternationWeight:Float;
	public var depthPriorFourthWeight:Float;
	public var equalityOneFiveWeight:Float;
	public var channelWeight:Float;
	public var throwOverWeight:Float;
	/** Preferred depth of 4th into prior 4th zone — soft. */
	public var depthIntoPriorFourth:Float;

	// --- Ch4 wave-specific target tables (length = fixed for JIT shape) ---
	/** Common W2 retrace targets of W1. */
	public var w2RetraceTargets:haxe.ds.Vector<Float>;
	public var w2RetraceN:Int;
	public var w4RetraceTargets:haxe.ds.Vector<Float>;
	public var w4RetraceN:Int;
	public var w3ExtTargets:haxe.ds.Vector<Float>;
	public var w3ExtN:Int;
	public var w5ExtTargets:haxe.ds.Vector<Float>;
	public var w5ExtN:Int;
	public var zigBTargets:haxe.ds.Vector<Float>;
	public var zigBTargetsN:Int;
	public var zigCTargets:haxe.ds.Vector<Float>;
	public var zigCTargetsN:Int;
	public var timeMultipleTargets:haxe.ds.Vector<Float>;
	public var timeMultipleN:Int;

	public function new() {
		handbookDefaults();
	}

	/** Frost/Prechter textbook defaults. */
	public function handbookDefaults():Void {
		phi = 1.6180339887;
		phiInv = 0.6180339887;
		phiSq = 2.6180339887;
		oneMinusPhiInv = 0.3819660113;
		half = 0.5;
		sqrtPhiInvApprox = 0.786;
		phiExt1272 = 1.272;
		phiExt1618 = 1.6180339887;
		phiExt2618 = 2.6180339887;
		phiExt4236 = 4.236;

		fibHitTol = 0.10;
		timeHitTol = 0.35;
		equalityTol = 0.12;

		zigzagBMin = 0.382;
		zigzagBMax = 0.99;
		zigzagCMinVsA = 0.618;

		flatBNear = 0.90;
		flatBBeyond = 0.05;
		flatCVsA = 1.0;

		alternationWeight = 1.0;
		depthPriorFourthWeight = 1.0;
		equalityOneFiveWeight = 1.0;
		channelWeight = 0.8;
		throwOverWeight = 0.6;
		depthIntoPriorFourth = 1.0;

		w2RetraceTargets = vec([0.5, 0.618, 0.786]);
		w2RetraceN = 3;
		w4RetraceTargets = vec([0.236, 0.382, 0.5]);
		w4RetraceN = 3;
		w3ExtTargets = vec([1.618, 2.0, 2.618]);
		w3ExtN = 3;
		w5ExtTargets = vec([0.618, 1.0, 1.618]);
		w5ExtN = 3;
		zigBTargets = vec([0.382, 0.5, 0.618]);
		zigBTargetsN = 3;
		zigCTargets = vec([1.0, 1.272, 1.618]);
		zigCTargetsN = 3;
		timeMultipleTargets = vec([0.618, 1.0, 1.618, 2.0]);
		timeMultipleN = 4;
	}

	static function vec(a:Array<Float>):haxe.ds.Vector<Float> {
		var v = new haxe.ds.Vector<Float>(a.length);
		for (i in 0...a.length) v[i] = a[i];
		return v;
	}

	/** Shallow copy of scalar fields + shared target vectors (immutable in practice). */
	public function clone():EwPhiParams {
		var p = new EwPhiParams();
		p.phi = phi; p.phiInv = phiInv; p.phiSq = phiSq;
		p.oneMinusPhiInv = oneMinusPhiInv; p.half = half;
		p.sqrtPhiInvApprox = sqrtPhiInvApprox;
		p.phiExt1272 = phiExt1272; p.phiExt1618 = phiExt1618;
		p.phiExt2618 = phiExt2618; p.phiExt4236 = phiExt4236;
		p.fibHitTol = fibHitTol; p.timeHitTol = timeHitTol; p.equalityTol = equalityTol;
		p.zigzagBMin = zigzagBMin; p.zigzagBMax = zigzagBMax; p.zigzagCMinVsA = zigzagCMinVsA;
		p.flatBNear = flatBNear; p.flatBBeyond = flatBBeyond; p.flatCVsA = flatCVsA;
		p.alternationWeight = alternationWeight;
		p.depthPriorFourthWeight = depthPriorFourthWeight;
		p.equalityOneFiveWeight = equalityOneFiveWeight;
		p.channelWeight = channelWeight; p.throwOverWeight = throwOverWeight;
		p.depthIntoPriorFourth = depthIntoPriorFourth;
		p.w2RetraceTargets = w2RetraceTargets; p.w2RetraceN = w2RetraceN;
		p.w4RetraceTargets = w4RetraceTargets; p.w4RetraceN = w4RetraceN;
		p.w3ExtTargets = w3ExtTargets; p.w3ExtN = w3ExtN;
		p.w5ExtTargets = w5ExtTargets; p.w5ExtN = w5ExtN;
		p.zigBTargets = zigBTargets; p.zigBTargetsN = zigBTargetsN;
		p.zigCTargets = zigCTargets; p.zigCTargetsN = zigCTargetsN;
		p.timeMultipleTargets = timeMultipleTargets; p.timeMultipleN = timeMultipleN;
		return p;
	}

	/** Best soft hit of `ratio` against the first `n` entries of `targets`. */
	public function bestHit(ratio:Float, targets:haxe.ds.Vector<Float>, n:Int):Float {
		if (!Math.isFinite(ratio) || ratio <= 0 || n <= 0) return 0.0;
		var best = 0.0;
		var lim = n < targets.length ? n : targets.length;
		for (i in 0...lim) {
			var s = SoftScores.fibRatio(ratio, targets[i], fibHitTol);
			if (s > best) best = s;
		}
		return best;
	}

	static var GLOBAL:EwPhiParams = null;

	/** Process-wide pack (finetune can replace). */
	public static function current():EwPhiParams {
		if (GLOBAL == null) GLOBAL = new EwPhiParams();
		return GLOBAL;
	}

	public static function setCurrent(p:EwPhiParams):Void {
		GLOBAL = p != null ? p : new EwPhiParams();
	}

	/** Build params from a flat float map (offline finetune load). */
	public static function loadFromMap(m:Map<String, Float>):EwPhiParams {
		return musescript.indicators.offline.PhiParamsDump.applyMap(m, new EwPhiParams());
	}

	#if (sys || node)
	/** Load finetuned pack from JSON file (sys / Node CLI only). */
	public static function loadFromJsonFile(path:String):EwPhiParams {
		var m = musescript.indicators.offline.PhiParamsDump.loadMapFromJsonFile(path);
		return loadFromMap(m);
	}
	#end
}
