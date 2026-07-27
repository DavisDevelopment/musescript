package musescript.indicators.offline;

/**
 * Export EwPhiParams as a flat float map for offline finetune / backprop-adjacent trainers.
 * NEVER call from MuseIndicator.update hot path in a tight loop without need.
 */
class PhiParamsDump {
	public static function toMap(?params:musescript.indicators.ew.EwPhiParams):Map<String, Float> {
		var p = params != null ? params : musescript.indicators.ew.EwPhiParams.current();
		var m = new Map<String, Float>();
		m.set("phi", p.phi);
		m.set("phiInv", p.phiInv);
		m.set("phiSq", p.phiSq);
		m.set("oneMinusPhiInv", p.oneMinusPhiInv);
		m.set("half", p.half);
		m.set("sqrtPhiInvApprox", p.sqrtPhiInvApprox);
		m.set("phiExt1272", p.phiExt1272);
		m.set("phiExt1618", p.phiExt1618);
		m.set("phiExt2618", p.phiExt2618);
		m.set("phiExt4236", p.phiExt4236);
		m.set("fibHitTol", p.fibHitTol);
		m.set("timeHitTol", p.timeHitTol);
		m.set("equalityTol", p.equalityTol);
		m.set("zigzagBMin", p.zigzagBMin);
		m.set("zigzagBMax", p.zigzagBMax);
		m.set("zigzagCMinVsA", p.zigzagCMinVsA);
		m.set("flatBNear", p.flatBNear);
		m.set("flatBBeyond", p.flatBBeyond);
		m.set("flatCVsA", p.flatCVsA);
		m.set("alternationWeight", p.alternationWeight);
		m.set("depthPriorFourthWeight", p.depthPriorFourthWeight);
		m.set("equalityOneFiveWeight", p.equalityOneFiveWeight);
		m.set("channelWeight", p.channelWeight);
		m.set("throwOverWeight", p.throwOverWeight);
		for (i in 0...p.w2RetraceN) m.set('w2Retrace_$i', p.w2RetraceTargets[i]);
		for (i in 0...p.w3ExtN) m.set('w3Ext_$i', p.w3ExtTargets[i]);
		for (i in 0...p.w5ExtN) m.set('w5Ext_$i', p.w5ExtTargets[i]);
		for (i in 0...p.zigCTargetsN) m.set('zigC_$i', p.zigCTargets[i]);
		return m;
	}

	public static function applyMap(m:Map<String, Float>, ?into:musescript.indicators.ew.EwPhiParams):musescript.indicators.ew.EwPhiParams {
		var p = into != null ? into : musescript.indicators.ew.EwPhiParams.current().clone();
		inline function g(k:String, d:Float):Float return m.exists(k) ? m.get(k) : d;
		p.phi = g("phi", p.phi);
		p.phiInv = g("phiInv", p.phiInv);
		p.phiSq = g("phiSq", p.phiSq);
		p.oneMinusPhiInv = g("oneMinusPhiInv", p.oneMinusPhiInv);
		p.half = g("half", p.half);
		p.fibHitTol = g("fibHitTol", p.fibHitTol);
		p.zigzagBMin = g("zigzagBMin", p.zigzagBMin);
		p.zigzagBMax = g("zigzagBMax", p.zigzagBMax);
		p.alternationWeight = g("alternationWeight", p.alternationWeight);
		return p;
	}
}
