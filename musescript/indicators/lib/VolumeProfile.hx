package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Volume Profile output: the price domain plus the per-bin volume histogram. */
typedef VolumeProfileOutput = {
	var priceLow:Float;
	var priceHigh:Float;
	var bins:Array<Float>;
}

/**
 * Volume Profile — ported from wickra-core's `VolumeProfile`
 * (vendor/wickra/crates/wickra-core/src/indicators/volume_profile.rs).
 *
 * Rolling Volume Profile over the last `period` candles. Where `ValueArea`
 * reduces the same volume distribution to its summary levels (POC/VAH/VAL),
 * Volume Profile exposes the full histogram. Each candle's volume is spread
 * uniformly across the bins its `[low, high]` range touches; a single-print
 * bar drops its whole volume into one bin. The histogram domain spans the
 * window's lowest low to its highest high; a window whose bars are all
 * single-print at one price puts the entire volume in bin 0 with both edges
 * collapsed to that price.
 */
class VolumeProfile implements MuseIndicator<Bar, VolumeProfileOutput> {
	var period:Int;
	var binCount:Int;
	var window:Array<Bar>;
	var last:Null<VolumeProfileOutput>;

	public function new(period:Int, binCount:Int) {
		if (period <= 0 || binCount <= 0) throw "VolumeProfile: period and bin_count must be > 0";
		this.period = period;
		this.binCount = binCount;
		this.window = [];
		this.last = null;
	}

	/** Classic Volume Profile: 20-bar rolling window, 50 bins. */
	public static function classic():VolumeProfile {
		return new VolumeProfile(20, 50);
	}

	/** Configured `(period, bin_count)`. */
	public function params():{period:Int, binCount:Int} {
		return {period: period, binCount: binCount};
	}

	/** Most recent profile if available. */
	public function value():Null<VolumeProfileOutput> return last;

	function priceToBin(price:Float, winLow:Float, binWidth:Float):Int {
		var raw = Math.ffloor((price - winLow) / binWidth);
		var max = binCount - 1;
		if (raw < 0.0) return 0;
		if (raw > max) return max;
		return Std.int(raw);
	}

	function compute():VolumeProfileOutput {
		var winLow = Math.POSITIVE_INFINITY;
		var winHigh = Math.NEGATIVE_INFINITY;
		for (b in window) {
			if (b.low < winLow) winLow = b.low;
			if (b.high > winHigh) winHigh = b.high;
		}
		var span = winHigh - winLow;
		var bins = [for (_ in 0...binCount) 0.0];

		if (span <= 0.0) {
			// All bars are single-print at the same price.
			var total = 0.0;
			for (b in window) total += b.volume;
			bins[0] = total;
			return {priceLow: winLow, priceHigh: winLow, bins: bins};
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

		return {priceLow: winLow, priceHigh: winHigh, bins: bins};
	}

	public function update(bar:Bar):Null<VolumeProfileOutput> {
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
	public function name():String return "VolumeProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "volume_profile", args: [TWindow, TWindow], ret: TObject([
				{name: "priceLow", ty: TScalar}, {name: "priceHigh", ty: TScalar}, {name: "bins", ty: TVector}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 50);
				var nanFill:VolumeProfileOutput = {priceLow: Math.NaN, priceHigh: Math.NaN, bins: [for (_ in 0...b) Math.NaN]};
				return IndicatorCache.evalBar(h, "volume_profile:" + p + ":" + b, nanFill,
					() -> new VolumeProfile(p, b), (i, bar) -> (cast i : VolumeProfile).update(bar));
			}
		};
	}
}
