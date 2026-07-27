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
 * Truncation → cautious (shrunk) bands; extension → W5 mix bias.
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
		if (ImpulseRules.isImpulseFamily(h.label) || ImpulseRules.isDiagonalFamily(h.label)) {
			if (o + 5 >= scratch.length) return null;
			var ext = 0;
			var kind = "impulseW5";
			if (h.label == "impulse5_trunc") {
				kind = "impulseW5_trunc";
				ext = 0;
			} else if (h.label == "impulse5_ext1") {
				kind = "impulseW5_ext1";
				ext = 1;
			} else if (h.label == "impulse5_ext3") {
				kind = "impulseW5_ext3";
				ext = 3;
			} else if (h.label == "impulse5_ext5") {
				kind = "impulseW5_ext5";
				ext = 5;
			} else if (ImpulseRules.isDiagonalFamily(h.label)) {
				kind = h.label == "diagonal_leading" ? "diagonalLeadW5" : "diagonalEndW5";
				ext = ImpulseRules.extensionWhich(scratch, o, p);
			} else {
				ext = ImpulseRules.extensionWhich(scratch, o, p);
			}
			var targets = EwRatioTargets.wave5TargetsExt(scratch[o], scratch[o + 1], scratch[o + 4], ext, p);
			var times = EwRatioTargets.timeBars(scratch[o + 4].bar, scratch[o + 1].bar - scratch[o].bar, p);
			var band = bandFromTargets(targets, times, kind);
			if (h.label == "impulse5_trunc") {
				band = shrinkBand(band, scratch[o + 3].price, p.truncProjectShrink);
			}
			return band;
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
		if (h.label == "double_three") {
			if (o + 7 >= scratch.length) return null;
			var targets = EwRatioTargets.zigzagCTargets(scratch[o + 4], scratch[o + 5], scratch[o + 6], p);
			var times = EwRatioTargets.timeBars(scratch[o + 6].bar, scratch[o + 5].bar - scratch[o + 4].bar, p);
			return bandFromTargets(targets, times, "doubleThreeZ");
		}
		if (h.label == "triangle" || h.label == "triangle_expanding") {
			if (o + 5 >= scratch.length) return null;
			// Post-triangle thrust ≈ widest triangle span
			var a0 = scratch[o].price;
			var a1 = scratch[o + 1].price;
			var span = Math.abs(a1 - a0);
			var tip = scratch[o + 5];
			var dir = tip.price >= scratch[o + 4].price ? 1.0 : -1.0;
			var prices = new haxe.ds.Vector<Float>(3);
			prices[0] = tip.price + dir * span * p.phiInv;
			prices[1] = tip.price + dir * span;
			prices[2] = tip.price + dir * span * p.phi;
			var times = EwRatioTargets.timeBars(tip.bar, scratch[o + 1].bar - scratch[o].bar, p);
			return bandFromTargets(prices, times, h.label == "triangle_expanding" ? "triangleThrustExp" : "triangleThrust");
		}
		return null;
	}

	/** Shrink price band toward `anchor` (W3 tip under truncation). */
	static function shrinkBand(band:EwProjectBand, anchor:Float, shrink:Float):EwProjectBand {
		var s = shrink < 0.05 ? 0.05 : (shrink > 1.0 ? 1.0 : shrink);
		var midP = (band.priceLo + band.priceHi) * 0.5;
		var halfP = (band.priceHi - band.priceLo) * 0.5 * s;
		// Pull midpoint toward anchor (cautious: don't chase far past failure tip)
		var pulled = midP * (1.0 - 0.35) + anchor * 0.35;
		var midB = (band.barLo + band.barHi) * 0.5;
		var halfB = (band.barHi - band.barLo) * 0.5 * s;
		return {
			priceLo: pulled - halfP,
			priceHi: pulled + halfP,
			barLo: midB - halfB,
			barHi: midB + halfB,
			status: Projected,
			kind: band.kind
		};
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
