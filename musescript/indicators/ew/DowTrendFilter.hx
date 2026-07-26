package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Dow-theory style trend filter over SwingGraph: HH/HL = up, LH/LL = down.
 */
enum abstract DowBias(Int) from Int to Int {
	var Up = 1;
	var Down = -1;
	var Neutral = 0;
}

class DowTrendFilter {
	public static function bias(g:SwingGraph):DowBias {
		var n = g.pivotCount();
		if (n < 4) return Neutral;

		var h0 = Math.NaN;
		var h1 = Math.NaN;
		var l0 = Math.NaN;
		var l1 = Math.NaN;
		var hiCount = 0;
		var loCount = 0;
		// Scan newest→oldest to pick last two highs/lows without allocating.
		var i = n - 1;
		while (i >= 0) {
			var p = g.pivotAt(i);
			if (p.direction > 0) {
				if (hiCount == 0) { h1 = p.price; hiCount = 1; }
				else if (hiCount == 1) { h0 = p.price; hiCount = 2; }
			} else {
				if (loCount == 0) { l1 = p.price; loCount = 1; }
				else if (loCount == 1) { l0 = p.price; loCount = 2; }
			}
			if (hiCount >= 2 && loCount >= 2) break;
			i--;
		}
		if (hiCount < 2 || loCount < 2) return Neutral;
		if (h1 > h0 && l1 > l0) return Up;
		if (h1 < h0 && l1 < l0) return Down;
		return Neutral;
	}
}
