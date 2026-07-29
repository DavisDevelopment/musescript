package musescript.ew.auction;

import musescript.harness.Bar;

/**
 * Pure volume-at-price → value-area levels (POC + VAH/VAL).
 *
 * Deterministic: same bars / window / bins / pct → identical floats.
 * Volume is spread uniformly across bins touched by each bar's [low, high]
 * (single-print bars dump into one bin). Value area expands from the POC,
 * always absorbing the higher-volume neighbour next (ties break upward —
 * CME convention), until `valueAreaPct` of total volume is enclosed.
 */
typedef VolumeProfileLevels = {
	var poc:Float;
	var vaHigh:Float;
	var vaLow:Float;
	/** Actual enclosed volume / total (may exceed target slightly due to bins). */
	var valueAreaVolFrac:Float;
}

class VolumeProfile {
	/** Classic defaults: 20-bar window, 50 bins, 70% value area. */
	public static inline var DEFAULT_WINDOW:Int = 20;
	public static inline var DEFAULT_BINS:Int = 50;
	public static inline var DEFAULT_VALUE_AREA_PCT:Float = 0.70;

	/**
	 * Compute value-area levels from `bars` ending at `endInclusive`
	 * (default = last bar). Uses the last `window` bars ≤ endInclusive.
	 */
	public static function fromBars(
		bars:Array<Bar>,
		window:Int = DEFAULT_WINDOW,
		bins:Int = DEFAULT_BINS,
		valueAreaPct:Float = DEFAULT_VALUE_AREA_PCT,
		?endInclusive:Int
	):VolumeProfileLevels {
		if (bars == null || bars.length == 0)
			return nanLevels();
		if (window <= 0 || bins <= 0)
			return nanLevels();
		if (!(valueAreaPct > 0) || valueAreaPct > 1.0)
			return nanLevels();

		var end = endInclusive != null ? endInclusive : bars.length - 1;
		if (end < 0 || end >= bars.length) return nanLevels();
		var start = end - window + 1;
		if (start < 0) start = 0;
		if (end - start + 1 < 1) return nanLevels();

		return computeSlice(bars, start, end, bins, valueAreaPct);
	}

	static function computeSlice(
		bars:Array<Bar>, start:Int, end:Int, binCount:Int, valueAreaPct:Float
	):VolumeProfileLevels {
		var winLow = Math.POSITIVE_INFINITY;
		var winHigh = Math.NEGATIVE_INFINITY;
		for (i in start...(end + 1)) {
			var b = bars[i];
			if (b == null) continue;
			if (b.low < winLow) winLow = b.low;
			if (b.high > winHigh) winHigh = b.high;
		}
		if (!Math.isFinite(winLow) || !Math.isFinite(winHigh))
			return nanLevels();

		var span = winHigh - winLow;
		if (span <= 0.0) {
			// Flat window: everything collapses to the single price.
			return {
				poc: winLow,
				vaHigh: winLow,
				vaLow: winLow,
				valueAreaVolFrac: 1.0
			};
		}

		var hist = [for (_ in 0...binCount) 0.0];
		var binWidth = span / binCount;
		for (i in start...(end + 1)) {
			var b = bars[i];
			if (b == null || !(b.volume > 0)) continue;
			if (b.high <= b.low) {
				hist[priceToBin(b.low, winLow, binWidth, binCount)] += b.volume;
				continue;
			}
			var loIdx = priceToBin(b.low, winLow, binWidth, binCount);
			var hiIdx = priceToBin(b.high, winLow, binWidth, binCount);
			var share = b.volume / (hiIdx - loIdx + 1);
			for (j in loIdx...(hiIdx + 1)) hist[j] += share;
		}

		var total = 0.0;
		for (v in hist) total += v;
		if (!(total > 0)) {
			// No volume: geometric mid of the window range.
			var mid = (winLow + winHigh) * 0.5;
			return {poc: mid, vaHigh: winHigh, vaLow: winLow, valueAreaVolFrac: 0.0};
		}

		var pocIdx = 0;
		var pocVol = hist[0];
		for (i in 1...hist.length) {
			if (hist[i] > pocVol) {
				pocVol = hist[i];
				pocIdx = i;
			}
		}

		var target = total * valueAreaPct;
		var accumulated = pocVol;
		var lo = pocIdx;
		var hi = pocIdx;
		while (accumulated < target && (lo > 0 || hi + 1 < binCount)) {
			var canGoUp = hi + 1 < binCount;
			var canGoDown = lo > 0;
			var upV = canGoUp ? hist[hi + 1] : Math.NEGATIVE_INFINITY;
			var downV = canGoDown ? hist[lo - 1] : Math.NEGATIVE_INFINITY;
			if (canGoUp && (upV >= downV || !canGoDown)) {
				hi += 1;
				accumulated += upV;
			} else {
				lo -= 1;
				accumulated += downV;
			}
		}

		return {
			poc: winLow + binWidth * (pocIdx + 0.5),
			vaHigh: winLow + binWidth * (hi + 1.0),
			vaLow: winLow + binWidth * lo,
			valueAreaVolFrac: accumulated / total
		};
	}

	/**
	 * Bucket E3 — expose the volume histogram for golden / bin-sensitivity tests.
	 * Same windowing and binning as `fromBars`; returns empty array on degenerate input.
	 */
	public static function histogram(
		bars:Array<Bar>,
		window:Int = DEFAULT_WINDOW,
		bins:Int = DEFAULT_BINS,
		?endInclusive:Int
	):Array<Float> {
		var pack = histogramPack(bars, window, bins, endInclusive);
		return pack != null ? pack.vols : [];
	}

	/**
	 * Overlay-ready histogram: mid-bin `price` + `vol` (Initiative 2.4).
	 * Same windowing/binning as `fromBars` / `histogram`. Empty on degenerate input.
	 */
	public static function histogramBins(
		bars:Array<Bar>,
		window:Int = DEFAULT_WINDOW,
		bins:Int = DEFAULT_BINS,
		?endInclusive:Int
	):Array<{price:Float, vol:Float}> {
		var pack = histogramPack(bars, window, bins, endInclusive);
		if (pack == null) return [];
		var out:Array<{price:Float, vol:Float}> = [];
		for (i in 0...pack.vols.length) {
			out.push({
				price: pack.winLow + pack.binWidth * (i + 0.5),
				vol: pack.vols[i]
			});
		}
		return out;
	}

	static function histogramPack(
		bars:Array<Bar>,
		window:Int,
		bins:Int,
		?endInclusive:Int
	):Null<{vols:Array<Float>, winLow:Float, binWidth:Float}> {
		if (bars == null || bars.length == 0 || window <= 0 || bins <= 0)
			return null;
		var end = endInclusive != null ? endInclusive : bars.length - 1;
		if (end < 0 || end >= bars.length) return null;
		var start = end - window + 1;
		if (start < 0) start = 0;

		var winLow = Math.POSITIVE_INFINITY;
		var winHigh = Math.NEGATIVE_INFINITY;
		for (i in start...(end + 1)) {
			var b = bars[i];
			if (b == null) continue;
			if (b.low < winLow) winLow = b.low;
			if (b.high > winHigh) winHigh = b.high;
		}
		if (!Math.isFinite(winLow) || !Math.isFinite(winHigh)) return null;
		var span = winHigh - winLow;
		if (span <= 0.0) {
			return { vols: [for (_ in 0...bins) 0.0], winLow: winLow, binWidth: 0.0 };
		}

		var hist = [for (_ in 0...bins) 0.0];
		var binWidth = span / bins;
		for (i in start...(end + 1)) {
			var b = bars[i];
			if (b == null || !(b.volume > 0)) continue;
			if (b.high <= b.low) {
				hist[priceToBin(b.low, winLow, binWidth, bins)] += b.volume;
				continue;
			}
			var loIdx = priceToBin(b.low, winLow, binWidth, bins);
			var hiIdx = priceToBin(b.high, winLow, binWidth, bins);
			var share = b.volume / (hiIdx - loIdx + 1);
			for (j in loIdx...(hiIdx + 1)) hist[j] += share;
		}
		return { vols: hist, winLow: winLow, binWidth: binWidth };
	}

	static inline function priceToBin(price:Float, winLow:Float, binWidth:Float, binCount:Int):Int {
		var raw = Math.ffloor((price - winLow) / binWidth);
		var max = binCount - 1;
		if (raw < 0.0) return 0;
		if (raw > max) return max;
		return Std.int(raw);
	}

	static inline function nanLevels():VolumeProfileLevels {
		return {
			poc: Math.NaN,
			vaHigh: Math.NaN,
			vaLow: Math.NaN,
			valueAreaVolFrac: Math.NaN
		};
	}
}
