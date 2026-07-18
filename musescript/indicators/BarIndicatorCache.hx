package musescript.indicators;

import musescript.harness.Bar;

/**
 * Per-callsite cache of live `MuseIndicator` instances for bar-input
 * indicators (OBV, Aroon, CCI, MFI, WilliamsR, ...). Deliberately separate
 * from `IndicatorColumns`/`IndCol`: those key on identity of a RESOLVED
 * Float series array (rsi/ema/sma operate on `harness.series.get(name)`),
 * whereas indicators ported under `MuseIndicator` read the current Bar
 * directly every tick and own their internal streaming state — the cache's
 * only job is "same callsite -> same live object across bars", not value
 * storage, so it tracks "last bar index fed" instead of "source array
 * length consumed".
 */
class BarIndicatorCache {
	var entries:Map<String, {indicator:Dynamic, lastBarIndex:Int, lastValue:Dynamic}>;

	public function new() {
		entries = new Map();
	}

	public function reset():Void {
		entries = new Map();
	}

	/**
	 * Feed `bar` into the cached indicator for `key` (construct via `factory`
	 * on first use) unless this exact bar index was already consumed —
	 * guards against being queried more than once in the same bar (e.g. from
	 * both an `if` and a `when` referencing the same indicator call). Returns
	 * the latest output (null during warmup).
	 */
	public function update(key:String, bar:Bar, factory:Void->Dynamic, updateFn:Dynamic->Bar->Dynamic):Dynamic {
		var entry = entries.get(key);
		if (entry == null) {
			entry = { indicator: factory(), lastBarIndex: -1, lastValue: null };
			entries.set(key, entry);
		}
		if (bar.index != entry.lastBarIndex) {
			var out = updateFn(entry.indicator, bar);
			if (out != null) entry.lastValue = out;
			entry.lastBarIndex = bar.index;
		}
		return entry.lastValue;
	}
}
