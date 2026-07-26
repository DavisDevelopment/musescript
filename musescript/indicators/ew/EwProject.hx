package musescript.indicators.ew;

import musescript.indicators.geom.PivotStatus;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SwingGraph;

/** Projected price/time band tagged PivotStatus.Projected. */
typedef EwProjectBand = {
	var priceLo:Float;
	var priceHi:Float;
	var barLo:Float;
	var barHi:Float;
	var status:PivotStatus;
}

/**
 * Price/time projection bands from the latest Confirmed swing leg.
 * Bands are tagged Projected — never Confirmed.
 */
class EwProject {
	public static function fromLastLeg(g:SwingGraph, ratioLo:Float = 0.618, ratioHi:Float = 1.618):Null<EwProjectBand> {
		var n = g.pivotCount();
		if (n < 2) return null;
		var a = g.pivotAt(n - 2);
		var b = g.pivotAt(n - 1);
		var legBars = b.bar - a.bar;
		if (legBars <= 0) legBars = 1;
		var pLo = RatioEngine.projectLeg(a.price, b.price, b.price, ratioLo);
		var pHi = RatioEngine.projectLeg(a.price, b.price, b.price, ratioHi);
		return {
			priceLo: Math.min(pLo, pHi),
			priceHi: Math.max(pLo, pHi),
			barLo: b.bar + ratioLo * legBars,
			barHi: b.bar + ratioHi * legBars,
			status: Projected
		};
	}
}
