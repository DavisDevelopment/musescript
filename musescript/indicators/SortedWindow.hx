package musescript.indicators;

/**
 * Fixed-capacity rolling window that stays sorted ascending via binary
 * insert/remove, paired with a chronological `RingBuffer` for eviction.
 *
 * Replaces the `Array` + `.shift()` + `window.copy().sort()` pattern used by
 * rolling order-statistic indicators (median, quantile, VaR, IQR, …). Push is
 * O(n) for the sorted splice (still cheaper than a full O(n log n) re-sort once
 * `period` is larger than a handful of bars) and O(1) for ring eviction.
 *
 * Callers that previously sorted a scratch copy each bar should read order
 * statistics from `sorted` / `median` / `quantile` instead. Values must be
 * finite — non-finite inputs belong filtered at the indicator boundary, same
 * as before.
 */
class SortedWindow {
	var ring:RingBuffer<Float>;
	/** Ascending order statistics; length always equals `ring.length`. Do not mutate. */
	public var sorted(default, null):Array<Float>;
	var capacity:Int;

	public function new(capacity:Int) {
		if (capacity <= 0) throw "SortedWindow: capacity must be > 0";
		this.capacity = capacity;
		ring = new RingBuffer(capacity);
		sorted = [];
	}

	/**
	 * Append `v`. Once full, evicts the oldest chronologically and removes that
	 * same value from the sorted spine (exact Float identity — the ring returns
	 * the bit that was pushed). Returns the evicted value, or `null` while filling.
	 */
	public function push(v:Float):Null<Float> {
		// Capture fullness before push: on JS, `Null<Float>` of `0.0` is
		// indistinguishable from `null`, so we must not gate eviction on `!= null`.
		var wasFull = ring.isFull();
		var evicted = ring.push(v);
		if (wasFull) removeSorted(evicted);
		insertSorted(v);
		return wasFull ? evicted : null;
	}

	public var length(get, never):Int;
	inline function get_length():Int return ring.length;

	public inline function isFull():Bool return ring.isFull();

	/** Chronological oldest-first access — same as plain-Array window indexing. */
	public inline function oldest(i:Int):Float return ring.oldest(i);

	/** Ascending order statistic (`0` = minimum). */
	public inline function order(i:Int):Float return sorted[i];

	public function median():Float {
		var n = sorted.length;
		if (n == 0) return Math.NaN;
		if (n % 2 == 1) return sorted[Std.int(n / 2)];
		return (sorted[Std.int(n / 2) - 1] + sorted[Std.int(n / 2)]) / 2.0;
	}

	/**
	 * Type-7 / NumPy-default linearly interpolated quantile of the current
	 * sorted state (`quantile` in [0, 1]).
	 */
	public function quantile(quantile:Float):Float {
		return quantileSorted(sorted, quantile);
	}

	/** Linear-interpolated percentile with `pct` in [0, 100]. */
	public function percentile(pct:Float):Float {
		return quantileSorted(sorted, pct / 100.0);
	}

	/**
	 * Type-7 quantile of an already-sorted ascending array. Shared by indicators
	 * that still build a one-shot sorted scratch (e.g. MAD of absolute deviations).
	 */
	public static function quantileSorted(sorted:Array<Float>, quantile:Float):Float {
		var n = sorted.length;
		if (n == 0) return Math.NaN;
		if (n == 1) return sorted[0];
		var h = (n - 1) * quantile;
		var lower = Math.ffloor(h);
		var idx = Std.int(lower);
		if (idx >= n - 1) return sorted[n - 1];
		var frac = h - lower;
		return sorted[idx] + frac * (sorted[idx + 1] - sorted[idx]);
	}

	/** Oldest-to-newest chronological iterator (matches plain Array windows). */
	public inline function iterator():Iterator<Float> return ring.iterator();

	public function reset():Void {
		ring = new RingBuffer(capacity);
		sorted = [];
	}

	function insertSorted(v:Float):Void {
		var lo = 0;
		var hi = sorted.length;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (sorted[mid] < v) lo = mid + 1;
			else hi = mid;
		}
		sorted.insert(lo, v);
	}

	function removeSorted(v:Float):Void {
		var lo = 0;
		var hi = sorted.length;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (sorted[mid] < v) lo = mid + 1;
			else hi = mid;
		}
		// Exact Float match (ring eviction is identity-preserving). Skip any
		// less-than cluster and take the first equal; lower_bound already lands
		// on the leftmost equal when ties exist.
		if (lo < sorted.length && sorted[lo] == v) {
			sorted.splice(lo, 1);
			return;
		}
		// Defensive: floating equality should always hold for ring-roundtripped
		// values; fall back to a linear scan so a bad call can't corrupt length.
		for (i in 0...sorted.length) {
			if (sorted[i] == v) {
				sorted.splice(i, 1);
				return;
			}
		}
		throw "SortedWindow.removeSorted: value not found";
	}
}
