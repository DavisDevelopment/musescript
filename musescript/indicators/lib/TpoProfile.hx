package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** TPO Profile output: the price domain plus the per-bin time-period counts. */
typedef TpoProfileOutput = {
	var priceLow:Float;
	var priceHigh:Float;
	var counts:Array<Float>;
}

/**
 * TPO Profile — ported from wickra-core's `TpoProfile`
 * (vendor/wickra/crates/wickra-core/src/indicators/tpo_profile.rs).
 *
 * Rolling Time-Price-Opportunity (market-profile letter) distribution over
 * the last `period` candles. Where `VolumeProfile` distributes each bar's
 * *volume* across the bins it touches, the TPO profile counts *time*: every
 * period that trades at a price level contributes exactly one TPO mark
 * there (a full `+1` per touched bin, no sharing), regardless of volume.
 * A window whose bars are all single-print at one price is degenerate:
 * every period's mark lands in bin 0 and both edges collapse to that price.
 */
class TpoProfile implements MuseIndicator<Bar, TpoProfileOutput> {
	var period:Int;
	var binCount:Int;
	var window:RingBuffer<Bar>;
	var last:Null<TpoProfileOutput>;

	public function new(period:Int, binCount:Int) {
		if (period <= 0 || binCount <= 0) throw "TpoProfile: period and bin_count must be > 0";
		this.period = period;
		this.binCount = binCount;
		this.window = new RingBuffer(period);
		this.last = null;
	}

	/** Classic TPO Profile: 30-bar rolling window, 50 bins. */
	public static function classic():TpoProfile {
		return new TpoProfile(30, 50);
	}

	/** Configured `(period, bin_count)`. */
	public function params():{period:Int, binCount:Int} {
		return {period: period, binCount: binCount};
	}

	/** Most recent profile if available. */
	public function value():Null<TpoProfileOutput> return last;

	function priceToBin(price:Float, winLow:Float, binWidth:Float):Int {
		var raw = Math.ffloor((price - winLow) / binWidth);
		var max = binCount - 1;
		if (raw < 0.0) return 0;
		if (raw > max) return max;
		return Std.int(raw);
	}

	function compute():TpoProfileOutput {
		var winLow = Math.POSITIVE_INFINITY;
		var winHigh = Math.NEGATIVE_INFINITY;
		for (b in window) {
			if (b.low < winLow) winLow = b.low;
			if (b.high > winHigh) winHigh = b.high;
		}
		var span = winHigh - winLow;
		var counts = [for (_ in 0...binCount) 0.0];

		if (span <= 0.0) {
			// All bars are single-print at the same price: every period marks bin 0.
			counts[0] = window.length;
			return {priceLow: winLow, priceHigh: winLow, counts: counts};
		}

		var binWidth = span / binCount;
		for (b in window) {
			if (b.high <= b.low) {
				counts[priceToBin(b.low, winLow, binWidth)] += 1.0;
				continue;
			}
			var loIdx = priceToBin(b.low, winLow, binWidth);
			var hiIdx = priceToBin(b.high, winLow, binWidth);
			for (bin in loIdx...(hiIdx + 1)) {
				counts[bin] += 1.0;
			}
		}

		return {priceLow: winLow, priceHigh: winHigh, counts: counts};
	}

	public function update(bar:Bar):Null<TpoProfileOutput> {
		window.push(bar);
		if (window.length < period) return null;
		var out = compute();
		last = out;
		return out;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "TpoProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "tpo_profile", args: [TWindow, TWindow], ret: TObject([
				{name: "priceLow", ty: TScalar}, {name: "priceHigh", ty: TScalar}, {name: "counts", ty: TVector}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 30);
				var b = IndicatorCache.intArg(args, 1, 50);
				var nanFill:TpoProfileOutput = {priceLow: Math.NaN, priceHigh: Math.NaN, counts: [for (_ in 0...b) Math.NaN]};
				return IndicatorCache.evalBar(h, "tpo_profile:" + p + ":" + b, nanFill,
					() -> new TpoProfile(p, b), (i, bar) -> (cast i : TpoProfile).update(bar));
			}
		};
	}
}
