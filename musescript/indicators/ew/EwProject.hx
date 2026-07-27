package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.geom.SwingGraph;

/** Projected price/time band tagged PivotStatus.Projected. */
typedef EwProjectBand = {
	var priceLo:Float;
	var priceHi:Float;
	var barLo:Float;
	var barHi:Float;
	var status:PivotStatus;
	var kind:String;
}

/**
 * Wave-aware projections (Ch4) with generic last-leg fallback.
 * Bands are always Projected — never Confirmed.
 */
class EwProject {
	public static function fromLastLeg(g:SwingGraph, ?params:EwPhiParams):Null<EwProjectBand> {
		var p = params != null ? params : EwPhiParams.current();
		var n = g.pivotCount();
		if (n < 2) return null;
		var a = g.pivotAt(n - 2);
		var b = g.pivotAt(n - 1);
		var legBars = b.bar - a.bar;
		if (legBars <= 0) legBars = 1;
		var dir = b.price >= a.price ? 1.0 : -1.0;
		var mag = Math.abs(b.price - a.price);
		var pLo = b.price + dir * mag * p.phiInv;
		var pHi = b.price + dir * mag * p.phiExt1618;
		return {
			priceLo: Math.min(pLo, pHi),
			priceHi: Math.max(pLo, pHi),
			barLo: b.bar + p.phiInv * legBars,
			barHi: b.bar + p.phiExt1618 * legBars,
			status: Projected,
			kind: "lastLeg"
		};
	}

	public static function fromHypothesis(h:EwHypothesis, scratch:haxe.ds.Vector<PivotPoint>, ?params:EwPhiParams):Null<EwProjectBand> {
		var p = params != null ? params : EwPhiParams.current();
		if (h == null) return null;
		var o = h.offset;
		if (h.label == "impulse5" || h.label == "diagonal") {
			if (o + 5 >= scratch.length) return null;
			var targets = EwRatioTargets.wave5Targets(scratch[o], scratch[o + 1], scratch[o + 4], p);
			var times = EwRatioTargets.timeBars(scratch[o + 4].bar, scratch[o + 1].bar - scratch[o].bar, p);
			return bandFromTargets(targets, times, "impulseW5");
		}
		if (h.label == "zigzag" || h.label == "flat" || h.label == "flat_expanded" || h.label == "flat_running") {
			if (o + 3 >= scratch.length) return null;
			var targets = EwRatioTargets.zigzagCTargets(scratch[o], scratch[o + 1], scratch[o + 2], p);
			var times = EwRatioTargets.timeBars(scratch[o + 2].bar, scratch[o + 1].bar - scratch[o].bar, p);
			var kind = h.label == "zigzag" ? "zigzagC" : "flatC";
			return bandFromTargets(targets, times, kind);
		}
		if (h.label == "double_zigzag") {
			if (o + 7 >= scratch.length) return null;
			var targets = EwRatioTargets.zigzagCTargets(scratch[o + 4], scratch[o + 5], scratch[o + 6], p);
			var times = EwRatioTargets.timeBars(scratch[o + 6].bar, scratch[o + 5].bar - scratch[o + 4].bar, p);
			return bandFromTargets(targets, times, "doubleZigY");
		}
		return null;
	}

	static function bandFromTargets(prices:haxe.ds.Vector<Float>, bars:haxe.ds.Vector<Float>, kind:String):EwProjectBand {
		var plo = prices[0];
		var phi = prices[0];
		for (i in 1...prices.length) {
			if (prices[i] < plo) plo = prices[i];
			if (prices[i] > phi) phi = prices[i];
		}
		var blo = bars[0];
		var bhi = bars[0];
		for (i in 1...bars.length) {
			if (bars[i] < blo) blo = bars[i];
			if (bars[i] > bhi) bhi = bars[i];
		}
		return {
			priceLo: plo, priceHi: phi, barLo: blo, barHi: bhi,
			status: Projected, kind: kind
		};
	}
}
