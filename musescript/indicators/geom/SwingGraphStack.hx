package musescript.indicators.geom;

import musescript.harness.Bar;

/**
 * Two-threshold swing stack for Elliott degree nesting.
 *
 * Degree mapping (relative, not calendar-named):
 *   degree 0 — `fine` graph (smaller threshold → more pivots, inner waves)
 *   degree 1 — `coarse` graph (larger threshold → fewer pivots, outer structure)
 *
 * Each confirmed fine pivot carries an optional `parentIdx` into the coarse
 * graph: index of the newest coarse pivot whose bar is still ≤ the fine pivot bar.
 * Rebuilt incrementally on fine confirmation (indexed scan, no Array.shift).
 */
class SwingGraphStack {
	public var fine:SwingGraph;
	public var coarse:SwingGraph;

	var parentIdx:haxe.ds.Vector<Int>;
	var parentCap:Int;

	public function new(fineThreshold:Float = 0.05, ?coarseThreshold:Float, capacity:Int = 12) {
		if (coarseThreshold == null) coarseThreshold = Math.min(fineThreshold * 2.0, 0.25);
		fine = new SwingGraph(fineThreshold, capacity);
		coarse = new SwingGraph(coarseThreshold, capacity);
		parentCap = capacity;
		parentIdx = new haxe.ds.Vector<Int>(parentCap);
		for (i in 0...parentCap) parentIdx[i] = -1;
	}

	public inline function fineThreshold():Float return fine.thresholdFrac();
	public inline function coarseThreshold():Float return coarse.thresholdFrac();

	/** True when the fine graph confirmed a pivot this bar. */
	public function update(candle:Bar):Bool {
		coarse.update(candle);
		var confirmed = fine.update(candle);
		if (confirmed) {
			var fi = fine.pivotCount() - 1;
			linkFinePivot(fi);
		}
		return confirmed;
	}

	/**
	 * Coarse-graph index for fine pivot `fineIdx`, or -1 when no coarse pivot
	 * precedes the fine bar yet.
	 */
	public function parentIdxOf(fineIdx:Int):Int {
		if (fineIdx < 0 || fineIdx >= fine.pivotCount()) return -1;
		if (fineIdx < parentCap) return parentIdx[fineIdx];
		// Ring eviction: recompute on demand for retained tail
		return computeParentIdx(fine.pivotAt(fineIdx).bar);
	}

	function linkFinePivot(fineIdx:Int):Void {
		var slot = fineIdx;
		if (slot >= parentCap) slot = parentCap - 1;
		parentIdx[slot] = computeParentIdx(fine.pivotAt(fineIdx).bar);
	}

	function computeParentIdx(fineBar:Int):Int {
		var cn = coarse.pivotCount();
		if (cn == 0) return -1;
		var best = -1;
		var bestBar = -1;
		for (ci in 0...cn) {
			var cb = coarse.pivotAt(ci).bar;
			if (cb <= fineBar && cb >= bestBar) {
				bestBar = cb;
				best = ci;
			}
		}
		return best;
	}

	public function reset():Void {
		fine.reset();
		coarse.reset();
		for (i in 0...parentCap) parentIdx[i] = -1;
	}
}
