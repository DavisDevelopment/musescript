package musescript.indicators.geom;

import musescript.harness.Bar;

/**
 * Shared non-repainting percent-threshold swing substrate.
 *
 * Replaces the dozens of private `SwingTracker` copies under `indicators/lib/`.
 * Confirmed pivots live in a `PivotRing` (no `Array.shift`). The live candidate
 * is exposed as a Forming `PivotPoint` via `forming()` — its price/bar may move
 * until confirmation.
 *
 * `update` returns true when a Confirmed pivot was just pushed.
 */
class SwingGraph {
	var threshold:Float;
	var ring:PivotRing;
	var barsSeen:Int;
	var trackingHigh:Bool;
	var extreme:Float;
	var extremeBar:Int;
	var bootstrapped:Bool;
	var formingScratch:PivotPoint;
	var lastConfirmed:Bool;

	public function new(threshold:Float = 0.05, capacity:Int = 8) {
		if (!Math.isFinite(threshold) || threshold <= 0.0 || threshold >= 1.0)
			throw "SwingGraph: threshold must be a finite fraction in (0, 1)";
		if (capacity <= 0) throw "SwingGraph: capacity must be > 0";
		this.threshold = threshold;
		ring = new PivotRing(capacity);
		formingScratch = new PivotPoint(Math.NaN, 1.0, -1, Forming);
		reset();
	}

	public function thresholdFrac():Float return threshold;
	public function capacity():Int return ring.capacity;
	public function pivotCount():Int return ring.length;
	public inline function pivotAt(i:Int):PivotPoint return ring.at(i);
	public function newestPivot():Null<PivotPoint> return ring.newest();

	/** Bars observed (post-increment count). Current bar index = barsSeen - 1. */
	public function getBarsSeen():Int return barsSeen;
	public function currentBar():Int return barsSeen - 1;

	/**
	 * Live Forming candidate, or null before bootstrap. Reuses one object —
	 * callers must copy if they retain across bars.
	 */
	public function forming():Null<PivotPoint> {
		if (!bootstrapped) return null;
		formingScratch.price = extreme;
		formingScratch.direction = trackingHigh ? 1.0 : -1.0;
		formingScratch.bar = extremeBar;
		formingScratch.status = Forming;
		return formingScratch;
	}

	/** True when the last `update` confirmed a pivot. */
	public function didConfirm():Bool return lastConfirmed;

	/**
	 * Feed one bar. Returns true iff a Confirmed pivot was appended this bar.
	 */
	public function update(candle:Bar):Bool {
		var bar = barsSeen;
		barsSeen++;
		lastConfirmed = false;

		if (!bootstrapped) {
			bootstrapped = true;
			trackingHigh = true;
			extreme = candle.high;
			extremeBar = bar;
			return false;
		}

		if (trackingHigh) {
			if (candle.high > extreme) {
				extreme = candle.high;
				extremeBar = bar;
				return false;
			}
			if (candle.low <= extreme * (1.0 - threshold)) {
				ring.push(new PivotPoint(extreme, 1.0, extremeBar, Confirmed));
				trackingHigh = false;
				extreme = candle.low;
				extremeBar = bar;
				lastConfirmed = true;
				return true;
			}
			return false;
		} else {
			if (candle.low < extreme) {
				extreme = candle.low;
				extremeBar = bar;
				return false;
			}
			if (candle.high >= extreme * (1.0 + threshold)) {
				ring.push(new PivotPoint(extreme, -1.0, extremeBar, Confirmed));
				trackingHigh = true;
				extreme = candle.high;
				extremeBar = bar;
				lastConfirmed = true;
				return true;
			}
			return false;
		}
	}

	public function reset():Void {
		ring.clear();
		barsSeen = 0;
		bootstrapped = false;
		trackingHigh = true;
		extreme = Math.NaN;
		extremeBar = -1;
		lastConfirmed = false;
	}

	/** Compatibility: chronological Array of Confirmed pivots only. */
	public function getPivots():Array<PivotPoint> return ring.toArray();
}
