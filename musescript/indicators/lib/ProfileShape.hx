package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Profile Shape — ported from wickra-core's `ProfileShape`
 * (vendor/wickra/crates/wickra-core/src/indicators/profile_shape.rs).
 *
 * Classifies a rolling volume profile by where its point of control (POC)
 * sits within the range:
 * `+1` P-shape (POC in the upper third — short-covering / accumulation),
 * `-1` b-shape (POC in the lower third — long-liquidation / distribution),
 * `0` D/normal (POC in the middle third — balanced bell).
 * The first value lands after `period` candles.
 */
class ProfileShape implements MuseIndicator<Bar, Float> {
	var period:Int;
	var bins:Int;
	var window:Array<Bar>;
	var last:Null<Float>;

	public function new(period:Int, bins:Int) {
		if (period <= 0) throw "ProfileShape: period must be > 0";
		if (bins < 3) throw "ProfileShape: profile shape needs bins >= 3";
		this.period = period;
		this.bins = bins;
		this.window = [];
		this.last = null;
	}

	/** Configured `(period, bins)`. */
	public function params():{period:Int, bins:Int} {
		return {period: period, bins: bins};
	}

	/** Current value if available. */
	public function value():Null<Float> return last;

	function pocIndex():Int {
		var low = Math.POSITIVE_INFINITY;
		var high = Math.NEGATIVE_INFINITY;
		for (c in window) {
			if (c.low < low) low = c.low;
			if (c.high > high) high = c.high;
		}
		var hist = [for (_ in 0...bins) 0.0];
		var span = high - low;
		if (span > 0.0) {
			var width = span / bins;
			for (c in window) {
				if (c.volume == 0.0) continue;
				var loIdx = clampBin(Math.ffloor((c.low - low) / width));
				var hiIdx = clampBin(Math.ffloor((c.high - low) / width));
				var share = c.volume / (hiIdx - loIdx + 1);
				for (bin in loIdx...(hiIdx + 1)) {
					hist[bin] += share;
				}
			}
		}
		var pocIdx = 0;
		var pocVol = Math.NEGATIVE_INFINITY;
		for (idx in 0...hist.length) {
			if (hist[idx] > pocVol) {
				pocVol = hist[idx];
				pocIdx = idx;
			}
		}
		return pocIdx;
	}

	inline function clampBin(raw:Float):Int {
		var idx = Std.int(raw);
		return idx < bins - 1 ? idx : bins - 1;
	}

	public function update(bar:Bar):Null<Float> {
		if (window.length == period) window.shift();
		window.push(bar);
		if (window.length < period) return null;
		var poc = pocIndex();
		var lower = Std.int(bins / 3);
		var upper = bins - Std.int(bins / 3);
		var shape = poc >= upper ? 1.0 : (poc < lower ? -1.0 : 0.0);
		last = shape;
		return shape;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "ProfileShape";

	public static function spec():IndicatorSpec {
		return {
			name: "profile_shape", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 24);
				return IndicatorCache.evalBar(h, "profile_shape:" + p + ":" + b, Math.NaN,
					() -> new ProfileShape(p, b), (i, bar) -> (cast i : ProfileShape).update(bar));
			}
		};
	}
}
