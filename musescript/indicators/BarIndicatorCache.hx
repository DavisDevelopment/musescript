package musescript.indicators;

/**
 * Per-callsite cache of live `MuseIndicator` instances (OBV, MACD, RSI-Wilder,
 * ...). Deliberately separate from `IndicatorColumns`/`IndCol`: those key on
 * identity of a RESOLVED Float series array, whereas a `MuseIndicator` owns
 * its own streaming state and is fed one input per new bar — the cache's only
 * job is "same callsite → same live object across bars, fed at most once per
 * bar", not value storage.
 *
 * The IndicatorCache helpers (evalBar / evalSeries / evalPair) sit on top of
 * this and do the input extraction; this class is just the keyed store + the
 * once-per-bar guard.
 */
class BarIndicatorCache {
	var entries:Map<String, {instance:Dynamic, lastBarIndex:Int, lastValue:Dynamic}>;

	public function new() {
		entries = new Map();
	}

	public function reset():Void {
		entries = new Map();
	}

	/**
	 * Feed the cached instance for `key` (constructed via `factory` on first
	 * use) exactly once for bar `barIndex` — repeated queries in the same bar
	 * (e.g. from both an `if` and a `when` on the same indicator call) reuse
	 * the already-computed value rather than double-advancing the stream.
	 * `produce(instance)` performs the actual `update(...)` and returns its
	 * output; a null output leaves `lastValue` at the previous emitted value.
	 */
	public function feed(key:String, barIndex:Int, factory:Void->Dynamic, produce:Dynamic->Dynamic):Dynamic {
		var entry = entries.get(key);
		if (entry == null) {
			entry = { instance: factory(), lastBarIndex: -1, lastValue: null };
			entries.set(key, entry);
		}
		if (barIndex != entry.lastBarIndex) {
			var out = produce(entry.instance);
			if (out != null) entry.lastValue = out;
			entry.lastBarIndex = barIndex;
		}
		return entry.lastValue;
	}
}
