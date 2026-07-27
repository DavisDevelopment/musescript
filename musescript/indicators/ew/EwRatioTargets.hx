package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.geom.RatioEngine;

/**
 * Ch4 ratio / time projectors — Louisli cookbook as named EwPhiParams tables.
 * All targets come from params (finetune-shaped).
 */
class EwRatioTargets {
	/** Project W2 retracement levels of W1 as prices from W1 tip. */
	public static function wave2RetracePrices(p0:PivotPoint, p1:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		return projectRetraces(p0.price, p1.price, p.w2RetraceTargets, p.w2RetraceN);
	}

	public static function wave4RetracePrices(p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		return projectRetraces(p2.price, p3.price, p.w4RetraceTargets, p.w4RetraceN);
	}

	/** W3 extension targets measured from W2 end as multiples of W1. */
	public static function wave3ExtensionPrices(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var out = new haxe.ds.Vector<Float>(p.w3ExtN);
		var w1 = p1.price - p0.price;
		for (i in 0...p.w3ExtN) {
			out[i] = p2.price + w1 * p.w3ExtTargets[i];
		}
		return out;
	}

	public static function wave5Targets(p0:PivotPoint, p1:PivotPoint, p4:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var out = new haxe.ds.Vector<Float>(p.w5ExtN);
		var w1 = p1.price - p0.price;
		for (i in 0...p.w5ExtN) {
			out[i] = p4.price + w1 * p.w5ExtTargets[i];
		}
		return out;
	}

	/**
	 * Extension-aware W5 targets. `extWhich` is 0/1/3/5 from ImpulseRules.extensionWhich.
	 * Ext-3: shallower typical W5 (equality / φ⁻¹ of W1). Ext-5: stretch toward φ / φ² of W1.
	 * Ext-1: W5 often ≈ W3 remainder — still project from W1 multiples but damp extremes.
	 */
	public static function wave5TargetsExt(p0:PivotPoint, p1:PivotPoint, p4:PivotPoint, extWhich:Int, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var base = wave5Targets(p0, p1, p4, p);
		if (extWhich == 0) return base;
		var w1 = p1.price - p0.price;
		var out = new haxe.ds.Vector<Float>(base.length);
		for (i in 0...base.length) {
			var mult = p.w5ExtTargets[i < p.w5ExtN ? i : p.w5ExtN - 1];
			if (extWhich == 3) {
				// Prefer 0.618 / 1.0 of W1 after extended third
				mult = i == 0 ? p.phiInv : (i == 1 ? 1.0 : p.phiInv * p.phi);
			} else if (extWhich == 5) {
				mult = p.w5ExtTargets[i < p.w5ExtN ? i : 0] * p.ext5ProjectStretch;
			} else if (extWhich == 1) {
				mult = i == 0 ? p.oneMinusPhiInv : (i == 1 ? p.half : p.phiInv);
			}
			out[i] = p4.price + w1 * mult;
		}
		return out;
	}

	/** Shallow W4 retrace prices when W3 is extended (bias toward prior fourth territory). */
	public static function wave4RetracePricesExt3(p2:PivotPoint, p3:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var shallow = new haxe.ds.Vector<Float>(3);
		shallow[0] = Math.min(p.oneMinusPhiInv, p.w4RetraceTargets[0]);
		shallow[1] = p.oneMinusPhiInv;
		shallow[2] = p.half;
		return projectRetraces(p2.price, p3.price, shallow, 3);
	}

	public static function zigzagCTargets(p0:PivotPoint, p1:PivotPoint, p2:PivotPoint, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var out = new haxe.ds.Vector<Float>(p.zigCTargetsN);
		for (i in 0...p.zigCTargetsN) {
			out[i] = RatioEngine.projectLeg(p0.price, p1.price, p2.price, p.zigCTargets[i]);
		}
		return out;
	}

	/** Time targets: bar offsets from `fromBar` as multiples of `legBars`. */
	public static function timeBars(fromBar:Int, legBars:Int, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		var lb = legBars < 1 ? 1 : legBars;
		var out = new haxe.ds.Vector<Float>(p.timeMultipleN);
		for (i in 0...p.timeMultipleN) {
			out[i] = fromBar + p.timeMultipleTargets[i] * lb;
		}
		return out;
	}

	/**
	 * Louisli-style geometric blend: p_h^a * p_l^(1-a) for semi-log correction levels.
	 * Exponents from φ family params.
	 */
	public static function geometricBlend(high:Float, low:Float, ?params:EwPhiParams):haxe.ds.Vector<Float> {
		var p = params != null ? params : EwPhiParams.current();
		if (!(high > 0) || !(low > 0)) {
			var z = new haxe.ds.Vector<Float>(4);
			for (i in 0...4) z[i] = Math.NaN;
			return z;
		}
		var out = new haxe.ds.Vector<Float>(4);
		// Louisli high_low geometric blends; 0.382/0.618 from params
		out[0] = Math.pow(high, 0.125) * Math.pow(low, 0.875);
		out[1] = Math.pow(high, 0.236) * Math.pow(low, 0.764);
		out[2] = Math.pow(high, p.oneMinusPhiInv) * Math.pow(low, p.phiInv);
		out[3] = Math.pow(high, p.half) * Math.pow(low, p.half);
		return out;
	}

	static function projectRetraces(start:Float, end:Float, targets:haxe.ds.Vector<Float>, n:Int):haxe.ds.Vector<Float> {
		var out = new haxe.ds.Vector<Float>(n);
		var range = end - start;
		for (i in 0...n) {
			out[i] = end - range * targets[i];
		}
		return out;
	}
}
