package musescript.indicators.ew;

import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Mono-wave classification of consecutive Confirmed pivots.
 * Hard rules only (v1): direction alternation + minimum magnitude.
 */
enum abstract MonoWaveKind(Int) from Int to Int {
	var ImpulseCandidate = 1;
	var CorrectiveCandidate = 2;
	var Unknown = 0;
}

typedef MonoWave = {
	var kind:MonoWaveKind;
	var startBar:Int;
	var endBar:Int;
	var startPrice:Float;
	var endPrice:Float;
	var magnitude:Float;
	var direction:Float;
}

class MonoWaveRules {
	/** Classify last completed leg between pivots[i] and pivots[i+1]. */
	public static function classifyLeg(a:PivotPoint, b:PivotPoint, minFrac:Float = 0.0):MonoWave {
		var mag = Math.abs(b.price - a.price);
		var dir = b.price >= a.price ? 1.0 : -1.0;
		var kind:MonoWaveKind = Unknown;
		if (mag > 0 && (minFrac <= 0 || mag / Math.max(Math.abs(a.price), 1e-12) >= minFrac)) {
			// Alternating extremes already enforced by SwingGraph; treat as impulse candidate
			// when direction matches the completed extreme's polarity (high after up-leg).
			kind = (dir > 0 && b.direction > 0) || (dir < 0 && b.direction < 0)
				? ImpulseCandidate
				: CorrectiveCandidate;
		}
		return {
			kind: kind,
			startBar: a.bar,
			endBar: b.bar,
			startPrice: a.price,
			endPrice: b.price,
			magnitude: mag,
			direction: dir
		};
	}

	/** Fill out[0..n-2] from SwingGraph Confirmed pivots. Returns count. */
	public static function classifyGraph(g:SwingGraph, out:haxe.ds.Vector<MonoWave>, minFrac:Float = 0.0):Int {
		var n = g.pivotCount();
		if (n < 2) return 0;
		var count = 0;
		var max = out.length;
		for (i in 0...n - 1) {
			if (count >= max) break;
			out[count++] = classifyLeg(g.pivotAt(i), g.pivotAt(i + 1), minFrac);
		}
		return count;
	}
}
