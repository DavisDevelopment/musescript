package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Value Area output: Point of Control, Value Area High and Value Area Low. */
typedef ValueAreaOutput = {
	var poc:Float;
	var vah:Float;
	var val:Float;
}

/**
 * Value Area — ported from wickra-core's `ValueArea`
 * (vendor/wickra/crates/wickra-core/src/indicators/value_area.rs).
 *
 * Market-profile-style volume distribution over the last `period` candles,
 * bucketed into `bin_count` price bins. Each candle's volume is spread
 * uniformly across its `[low, high]` range; single-print bars dump their
 * whole volume into one bin. The Point of Control (POC) is the bin with the
 * highest cumulative volume; the Value Area expands outward from the POC,
 * always absorbing the higher-volume neighbour next (ties break upward,
 * matching the CME convention), until `value_area_pct` of total volume is
 * enclosed.
 */
class ValueArea implements MuseIndicator<Bar, ValueAreaOutput> {
	var period:Int;
	var binCount:Int;
	var valueAreaPct:Float;
	var window:Array<Bar>;
	var last:Null<ValueAreaOutput>;

	public function new(period:Int, binCount:Int, valueAreaPct:Float) {
		if (period <= 0 || binCount <= 0) throw "ValueArea: period and bin_count must be > 0";
		if (!Math.isFinite(valueAreaPct) || valueAreaPct <= 0.0 || valueAreaPct > 1.0) {
			throw "ValueArea: value_area_pct must be in (0, 1]";
		}
		this.period = period;
		this.binCount = binCount;
		this.valueAreaPct = valueAreaPct;
		this.window = [];
		this.last = null;
	}

	/** Classic Value Area: 20-bar rolling window, 50 bins, 70% concentration. */
	public static function classic():ValueArea {
		return new ValueArea(20, 50, 0.70);
	}

	/** Configured `(period, bin_count, value_area_pct)`. */
	public function params():{period:Int, binCount:Int, valueAreaPct:Float} {
		return {period: period, binCount: binCount, valueAreaPct: valueAreaPct};
	}

	/** Most recent output if available. */
	public function value():Null<ValueAreaOutput> return last;

	function priceToBin(price:Float, winLow:Float, binWidth:Float):Int {
		var raw = Math.ffloor((price - winLow) / binWidth);
		var max = binCount - 1;
		if (raw < 0.0) return 0;
		if (raw > max) return max;
		return Std.int(raw);
	}

	function compute():ValueAreaOutput {
		var winLow = Math.POSITIVE_INFINITY;
		var winHigh = Math.NEGATIVE_INFINITY;
		for (b in window) {
			if (b.low < winLow) winLow = b.low;
			if (b.high > winHigh) winHigh = b.high;
		}
		var span = winHigh - winLow;
		var bins = [for (_ in 0...binCount) 0.0];

		if (span <= 0.0) {
			// All bars are single-print at the same price — POC = VAH = VAL = that price.
			return {poc: winLow, vah: winLow, val: winLow};
		}
		var binWidth = span / binCount;
		for (b in window) {
			if (b.volume == 0.0) continue;
			if (b.high <= b.low) {
				bins[priceToBin(b.low, winLow, binWidth)] += b.volume;
				continue;
			}
			var loIdx = priceToBin(b.low, winLow, binWidth);
			var hiIdx = priceToBin(b.high, winLow, binWidth);
			var share = b.volume / (hiIdx - loIdx + 1);
			for (i in loIdx...(hiIdx + 1)) {
				bins[i] += share;
			}
		}

		var total = 0.0;
		for (v in bins) total += v;

		var pocIdx = 0;
		var pocVol = bins[0];
		for (i in 1...bins.length) {
			if (bins[i] > pocVol) {
				pocVol = bins[i];
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
			var upV = canGoUp ? bins[hi + 1] : Math.NEGATIVE_INFINITY;
			var downV = canGoDown ? bins[lo - 1] : Math.NEGATIVE_INFINITY;
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
			vah: winLow + binWidth * (hi + 1.0),
			val: winLow + binWidth * lo
		};
	}

	public function update(bar:Bar):Null<ValueAreaOutput> {
		if (window.length == period) window.shift();
		window.push(bar);
		if (window.length < period) return null;
		var out = compute();
		last = out;
		return out;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "ValueArea";

	public static function spec():IndicatorSpec {
		return {
			name: "value_area", args: [TWindow, TWindow, TScalar], ret: TObject([
				{name: "poc", ty: TScalar}, {name: "vah", ty: TScalar}, {name: "val", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 50);
				var v = IndicatorCache.floatArg(args, 2, 0.70);
				var nanFill:ValueAreaOutput = {poc: Math.NaN, vah: Math.NaN, val: Math.NaN};
				return IndicatorCache.evalBar(h, "value_area:" + p + ":" + b + ":" + v, nanFill,
					() -> new ValueArea(p, b, v), (i, bar) -> (cast i : ValueArea).update(bar));
			}
		};
	}
}
