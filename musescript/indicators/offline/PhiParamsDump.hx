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
		m.set("depthIntoPriorFourth", p.depthIntoPriorFourth);
		for (i in 0...p.w2RetraceN) m.set('w2Retrace_$i', p.w2RetraceTargets[i]);
		for (i in 0...p.w4RetraceN) m.set('w4Retrace_$i', p.w4RetraceTargets[i]);
		for (i in 0...p.w3ExtN) m.set('w3Ext_$i', p.w3ExtTargets[i]);
		for (i in 0...p.w5ExtN) m.set('w5Ext_$i', p.w5ExtTargets[i]);
		for (i in 0...p.zigBTargetsN) m.set('zigB_$i', p.zigBTargets[i]);
		for (i in 0...p.zigCTargetsN) m.set('zigC_$i', p.zigCTargets[i]);
		for (i in 0...p.timeMultipleN) m.set('timeMultiple_$i', p.timeMultipleTargets[i]);
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
		p.sqrtPhiInvApprox = g("sqrtPhiInvApprox", p.sqrtPhiInvApprox);
		p.phiExt1272 = g("phiExt1272", p.phiExt1272);
		p.phiExt1618 = g("phiExt1618", p.phiExt1618);
		p.phiExt2618 = g("phiExt2618", p.phiExt2618);
		p.phiExt4236 = g("phiExt4236", p.phiExt4236);
		p.fibHitTol = g("fibHitTol", p.fibHitTol);
		p.timeHitTol = g("timeHitTol", p.timeHitTol);
		p.equalityTol = g("equalityTol", p.equalityTol);
		p.zigzagBMin = g("zigzagBMin", p.zigzagBMin);
		p.zigzagBMax = g("zigzagBMax", p.zigzagBMax);
		p.zigzagCMinVsA = g("zigzagCMinVsA", p.zigzagCMinVsA);
		p.flatBNear = g("flatBNear", p.flatBNear);
		p.flatBBeyond = g("flatBBeyond", p.flatBBeyond);
		p.flatCVsA = g("flatCVsA", p.flatCVsA);
		p.alternationWeight = g("alternationWeight", p.alternationWeight);
		p.depthPriorFourthWeight = g("depthPriorFourthWeight", p.depthPriorFourthWeight);
		p.equalityOneFiveWeight = g("equalityOneFiveWeight", p.equalityOneFiveWeight);
		p.channelWeight = g("channelWeight", p.channelWeight);
		p.throwOverWeight = g("throwOverWeight", p.throwOverWeight);
		p.depthIntoPriorFourth = g("depthIntoPriorFourth", p.depthIntoPriorFourth);
		applyVec(m, "w2Retrace", p.w2RetraceTargets, p.w2RetraceN);
		applyVec(m, "w4Retrace", p.w4RetraceTargets, p.w4RetraceN);
		applyVec(m, "w3Ext", p.w3ExtTargets, p.w3ExtN);
		applyVec(m, "w5Ext", p.w5ExtTargets, p.w5ExtN);
		applyVec(m, "zigB", p.zigBTargets, p.zigBTargetsN);
		applyVec(m, "zigC", p.zigCTargets, p.zigCTargetsN);
		applyVec(m, "timeMultiple", p.timeMultipleTargets, p.timeMultipleN);
		return p;
	}

	/** Plain object for haxe.Json.stringify (Map is not JSON-serializable). */
	public static function toObject(?params:musescript.indicators.ew.EwPhiParams):Dynamic {
		var m = toMap(params);
		var o:Dynamic = {};
		for (k in m.keys()) Reflect.setField(o, k, m.get(k));
		return o;
	}

	static function applyVec(m:Map<String, Float>, prefix:String, vec:haxe.ds.Vector<Float>, n:Int):Void {
		for (i in 0...n) {
			var k = prefix + "_" + i;
			if (m.exists(k)) vec[i] = m.get(k);
		}
	}

	#if (sys || node)
	public static function saveJsonFile(path:String, ?params:musescript.indicators.ew.EwPhiParams):Void {
		sys.io.File.saveContent(path, haxe.Json.stringify(toObject(params), null, "  ") + "\n");
	}

	public static function loadMapFromJsonFile(path:String):Map<String, Float> {
		var raw:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
		var m = new Map<String, Float>();
		if (raw == null) return m;
		for (k in Reflect.fields(raw)) {
			var v = Reflect.field(raw, k);
			if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) m.set(k, Std.parseFloat(Std.string(v)));
		}
		return m;
	}
	#end
}
